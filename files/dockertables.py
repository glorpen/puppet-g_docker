#!/usr/bin/env python
# -*- coding: utf-8 -*-

'''
Script to manage Docker iptable rules.

Swarm is not supported as you cannot disable Docker machinery to stop changing iptable rules for INGRESS.

With external key-value store, standalone containers can connect with themselves through overlay network driver
without any iptable rules.
Port publishing works by using bridge network, not overlay as it would be in Swarm mode.

@author: Arkadiusz Dzięgiel <arkadiusz.dziegiel@glorpen.pl>
'''

from __future__ import print_function

import docker
import logging
import json
from collections import OrderedDict
import itertools

#print(json.encoder.JSONEncoder(indent=2).encode(self._node))

class ConnectionException(Exception):
    pass

# TODO: dynamic rules in custom chains
# TODO: handle docker masquerade labels
# TODO: handle container published ports
# TODO: IPv6 nat support
# TODO: add ingress-network support (for real swarm)

#1. vagrant - done
#2. stworzyć docker swarm - done
#3. zobaczyć jak działa tam iptables=false - done

'''
puppet module będzie miał możliwość instlacji z src (dołączony skrypt) lub rpm (też dołączone?)
skrypt będzie musiał być uruchamiany przez systemd
skrypt będzie działał podobnie jak docker-hostdns:
- wstępnie nie musi samodzielnie się daemonizować
- interfejsy musza być posortowane w jakiś sposób by ponowne uruchmienie usługi nie mieszał za dużo (czas stworzenia? jak nie to nazwa)
- przy starcie następuje przeskanowanie wszystkich dostępnych interfejsów i kontenerów i stworzone są rules do iptables
- odczytywane są eventy o interfejsach i kontenerach a następnie dostosowane iptables
- konfiguracja usługi w pliku w /etc/docker-iptables.conf (plik ini?)
- możliwość przeładowania konfiguracji w locie
'''

class IPAddress(object):
    def __init__(self, ip, prefix_len=None):
        super(IPAddress, self).__init__()
        
        if "/" in ip:
            self.addr, l = ip.split("/", 1)
            self.prefix_len = int(l)
        else:
            self.addr = str(ip)
            self.prefix_len = int(prefix_len)
    
class NetworkConfig(object):
    def __init__(self, node):
        super(NetworkConfig, self).__init__()
        self._node = node
    
    DRIVER_BRIDGE = 'bridge'
    DRIVER_OVERLAY = 'overlay'
    DRIVER_NULL = 'null'
    DRIVER_HOST = 'host'
    
    @property
    def name(self):
        return self._node["Name"]
    
    @property
    def created_at(self):
        return self._node["Created"]
    
    @property
    def uses_ipv6(self):
        return self._node["EnableIPv6"]
    
    @property
    def is_ingress(self):
        return self._node['Ingress']
    
    @property
    def is_bridge(self):
        return self.driver == self.DRIVER_BRIDGE
    
    @property
    def is_overlay(self):
        return self.driver == self.DRIVER_OVERLAY
    
    @property
    def short_id(self):
        return self.id[:12]
    
    @property
    def id(self):
        return self._node["Id"]
    
    @property
    def driver(self):
        return self._node["Driver"]
    
    @property
    def nat(self):
        if self.is_bridge:
            return self.get_bool_option("com.docker.network.bridge.enable_ip_masquerade", True)
    
    @property
    def icc(self):
        if self.is_bridge:
            return self.get_bool_option("com.docker.network.bridge.enable_icc", True)
    
    def get_option(self, name, default=None):
        if name in self._node['Options']:
            return self._node['Options'][name]
        return default
    
    def get_bool_option(self, name, default=None):
        return self.get_option(name, default) in ("true", True)
    
    @property
    def attachable(self):
        return self._node['Attachable']
    
    @property
    def iface(self):
        if self.is_bridge:
            return self.get_option("com.docker.network.bridge.name", "br-%s" % self.short_id)
        elif not self.attachable:
            return None
        
        raise Exception("Not implemented")
    
    def get_subnets(self):
        return [c["Subnet"] for c in self._node["IPAM"]["Config"]]
    
    @property
    def ip4_subnets(self):
        return [i for i in self.get_subnets() if ":" not in i]
    
    @property
    def ip6_subnets(self):
        return [i for i in self.get_subnets() if ":" in i]
    
    @property
    def containers(self):
        ret = {}
        for k,c in self._node["Containers"].items():
            ret[k] = {
                "container_id": k,
                "network_name": self.name,
                "ipv4": IPAddress(c["IPv4Address"]) if c["IPv4Address"] else None,
                "ipv6": IPAddress(c["IPv6Address"]) if c["IPv6Address"] else None
            }
        return ret

class PortConfig(object):
    def __init__(self, proto, port, private_port, ip=None):
        super(PortConfig, self).__init__()
        
        self.protocol = proto
        self.port = port
        self.private_port = private_port
        self.ip = None if ip == '0.0.0.0' else ip
    
    def __repr__(self):
        return "%s:%d:%s" % (self.ip, self.port, self.protocol)

class ContainerConfig(object):
    def __init__(self, node):
        super(ContainerConfig, self).__init__()
        self._node = node
    
    @property
    def created_at(self):
        return self._node["Created"]
    
    @property
    def id(self):
        return self._node["Id"]
    
    @property
    def ports(self):
        return [PortConfig(i['Type'], i['PublicPort'], i['PrivatePort'], i['IP']) for i in self._node["Ports"]]
    
    @property
    def ip_addresses(self):
        ret = []
        for name, conf in self._node["NetworkSettings"]["Networks"].items():
            
            # skip invalid entries
            # happens when there is not default bridge given and no other networks are used in container
            if not conf["NetworkID"]:
                continue
            
            ret.append({
                "network_name": name,
                "ipv4": IPAddress(conf["IPAddress"], conf["IPPrefixLen"]) if conf["IPAddress"] else None,
                "ipv6": IPAddress(conf["GlobalIPv6Address"], conf["GlobalIPv6PrefixLen"]) if conf["GlobalIPv6Address"] else None,
            })
        return ret

class DockerHandler(object):
    
    client = None
    
    def __init__(self):
        super(DockerHandler, self).__init__()
        self.logger = logging.getLogger(self.__class__.__name__)
        self._hosts_cache = {}
    
    def setup(self):
        try:
            client = docker.from_env()
            client.ping()
        except Exception:
            raise ConnectionException('Error communicating with docker.')
        
        self.logger.info("Connected to docker")
        self.client = client
        
        self.load_containers()
    
    def _get_networks(self):
        networks = []
        for data in self.client.networks():
            n = NetworkConfig(data)
            networks.append((n.name, n))
        
        networks.sort(key=lambda x:x[1].created_at, reverse=True)
        return OrderedDict(networks)
    
    def _get_containers(self):
        containers = []
        for n in self.client.containers():
            cfg = ContainerConfig(n)
            containers.append((cfg.id, cfg))
        containers.sort(key=lambda x:x[1].created_at, reverse=True)
        return OrderedDict(containers)
    
    def load_containers(self):
        
        networks = self._get_networks()
        containers = self._get_containers()
        
        nat_rules = []
        nat6_rules = []
        docker_nat_rules = []
        docker_nat6_rules = []
        bridge_rules = []
        bridge6_rules = []
        isolation_rules = []
        isolation6_rules = []
        
        for n in networks.values():
            if n.is_bridge:
                #TODO add common rules to ip6tables
                nat_rules.append("-A POSTROUTING -o %s -m addrtype --src-type LOCAL -j MASQUERADE" % n.iface)
                
                if n.nat:
                    for subnet in n.ip4_subnets:
                        nat_rules.append("-A POSTROUTING -s %s ! -o %s -j MASQUERADE" % (subnet, n.iface))
                    for subnet in n.ip6_subnets:
                        nat6_rules.append("-A POSTROUTING -s %s ! -o %s -j MASQUERADE" % (subnet, n.iface))
                
                bridge_rules.append("-A FORWARD -o {iface} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT".format(iface = n.iface))
                bridge_rules.append("-A FORWARD -o {iface} -j DOCKER".format(iface = n.iface))
                bridge_rules.append("-A FORWARD -i {iface} ! -o {iface} -j ACCEPT".format(iface = n.iface))
                
                if n.icc:
                    bridge_rules.append("-A FORWARD -i {iface} -o {iface} -j ACCEPT".format(iface = n.iface))
                else:
                    bridge_rules.append("-A FORWARD -i {iface} -o {iface} -j DROP".format(iface = n.iface))
                
        
        
        for src, dst in itertools.permutations([n.iface for n in networks.values() if n.is_bridge], 2):
            isolation_rules.append("-A DOCKER-ISOLATION -i {src} -o {dst} -j DROP".format(
                src=src,
                dst=dst
            ))
        
        # for forwarding, docker always uses address from sorted list of bridge network interfaces
        for cfg in containers.values():
            ip4_conf = ip6_conf = None
            for i in filter(lambda x:networks[x["network_name"]].is_bridge, cfg.ip_addresses):
                if not ip4_conf and i["ipv4"]:
                    ip4_conf = i
                if not ip6_conf and i["ipv6"]:
                    ip6_conf = i
                    # if both ipv4 and ipv6 addresses are found, Docker uses that network
                    if i["ipv4"]:
                        ip4_conf = i
                
                if ip6_conf and ip4_conf:
                    break
            else:
                # when there is no bridge network and only overlay is available,
                # docker implictly uses docker_gwbridge (it is not reported in container inspect data)
                # so we have to find its ip address in network data
                
                # TODO: check ipv6 failover on docker_gwbridge
                
                ip_conf = networks["docker_gwbridge"].containers.get(cfg.id)
                if ip_conf:
                    if ip_conf["ipv6"]:
                        ip6_conf = ip_conf
                    if ip_conf["ipv4"]:
                        ip4_conf = ip_conf
            
            #TODO: ipv6
            #TODO: check udp
            if ip4_conf or ip6_conf:
                for p in cfg.ports:
                    if ip4_conf:
                        nat_rules.append("-A POSTROUTING -s {ip}/32 -d {ip}/32 -p {protocol} -m {protocol} --dport {port} -j MASQUERADE".format(
                            ip = ip4_conf["ipv4"].addr,
                            protocol = p.protocol,
                            port = p.private_port
                        ))
                        docker_nat_rules.append("-A DOCKER -p {protocol} -m {protocol} --dport {port} -j DNAT --to-destination {ip}:{private_port}".format(
                            ip = ip4_conf["ipv4"].addr,
                            protocol = p.protocol,
                            private_port = p.private_port,
                            port = p.port
                        ))
                        
                        bridge_rules.append("-A DOCKER -d {ip}/32 ! -i {iface} -o {iface} -p {protocol}  -m {protocol}  --dport {private_port} -j ACCEPT".format(
                            ip = ip4_conf["ipv4"].addr,
                            iface = networks[ip4_conf["network_name"]].iface,
                            protocol = p.protocol,
                            private_port = p.private_port,
                        ))
                    if ip6_conf:
                        nat6_rules.append("-A POSTROUTING -s {ip}/128 -d {ip}/128 -p {protocol} -m {protocol} --dport {port} -j MASQUERADE".format(
                            ip = ip6_conf["ipv6"].addr,
                            protocol = p.protocol,
                            port = p.private_port
                        ))
                        docker_nat6_rules.append("-A DOCKER -p {protocol} -m {protocol} --dport {port} -j DNAT --to-destination {ip}:{private_port}".format(
                            ip = "[%s]" % ip6_conf["ipv6"].addr,
                            protocol = p.protocol,
                            private_port = p.private_port,
                            port = p.port
                        ))
                        
                        bridge6_rules.append("-A DOCKER -d {ip}/128 ! -i {iface} -o {iface} -p {protocol}  -m {protocol}  --dport {private_port} -j ACCEPT".format(
                            ip = ip6_conf["ipv6"].addr,
                            iface = networks[ip6_conf["network_name"]].iface,
                            protocol = p.protocol,
                            private_port = p.private_port,
                        ))
        
        rules = nat_rules #+ docker_nat_rules + bridge_rules + isolation_rules
        rules = nat6_rules + docker_nat6_rules + bridge6_rules + isolation6_rules
        
        for r in rules:
            print(r)
    
    def on_disconnect(self, container_id):
        if container_id not in self._hosts_cache:
            self.logger.debug("Disconnected container %r was not tracked, ignoring", container_id)
            return
        name = self._hosts_cache[container_id]
        self.logger.info("Removing entry %r as container %r disconnected", name, container_id)
        del self._hosts_cache[container_id]
            
        self.dns_updater.remove_host(name)
    
    def on_connect(self, container_id, name, ipv4s, ipv6s):
        unique_name = self._deduplicate_container_name(name)
        self.logger.info("Adding new entry %r:{ipv4:%r, ipv6:%r} for container %r", unique_name, ipv4s, ipv6s, container_id)
        self._hosts_cache[container_id] = unique_name
        self.dns_updater.add_host(unique_name, ipv4s, ipv6s)
        
    def handle_event(self, event):
        if event["Type"] == "network":
            print(event)
#             if event["Action"] == "connect":
#                 container_id = event["Actor"]["Attributes"]["container"]
#                 #self.logger.debug("Handling connect event for container %r", container_id)
#                 #info = ContainerInfo.from_container(self.client.containers.get(container_id))
#                 #self.on_connect(container_id, info.name, info.ipv4s, info.ipv6s)
#             
#             if event["Action"] == "disconnect":
#                 #container_id = event["Actor"]["Attributes"]["container"]
#                 #self.logger.debug("Handling disconnect event for container %r", container_id)
#                 #self.on_disconnect(container_id)
#     
    def run(self):
        events = self.client.events(decode=True)
        
        while True:
            try:
                event = next(events)
            except docker.StopException:
                self.logger.info("Exitting")
                return
            except Exception:
                self.logger.info("Docker connection broken - exitting")
                return
            
            self.handle_event(event)

if __name__ == "__main__":
    
    logging.basicConfig(level=logging.DEBUG)
    
    d = DockerHandler()
    d.setup()
    #d.run()
    
    #nsenter --net=/var/run/docker/netns/ingress_sbox iptables-save
    # czy na node0 w NS pojawią się wpisy jeśli iptables=false? - tak, dodatkowo też są w zwykłym iptables
    # a co gdy etc będzie zamiast swarm init?
    