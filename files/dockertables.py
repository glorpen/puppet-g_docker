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
import contextlib

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

class Rule(object):
    _ipv4 = False
    _ipv6 = False
    
    _table = None
    _chain = None
    _data = None
    _group = None
    
    def __init__(self):
        super(Rule, self).__init__()
        self._tags = {}
    
    def rule(self, table, chain, data):
        self._table = table
        self._chain = chain
        self._data = data
        return self
    
    def ipv6(self, v=True):
        self._ipv6 = v
        return self
    
    def ipv4(self, v=True):
        self._ipv4 = v
        return self
    
    def ip_any(self):
        return self.ipv4().ipv6()
    
    def ip_type(self, name):
        if name == "ipv4":
            return self.ipv4()
        if name == "ipv6":
            return self.ipv6()
    
    # usunąć - użyć filtrowania po występujacych tagach (network/container)
    def group(self, group):
        self._group = group
        return self
    
    def tags(self, **kwargs):
        self._tags = kwargs
        return self
    
    def __repr__(self):
        return "-t %s -A %s %s" % (self._table, self._chain, self._data)

class RuleSet(object):
    
    GROUP_NETWORK = 1
    GROUP_CONTAINER = 2
    
    def __init__(self):
        super(RuleSet, self).__init__()
        self._rules = []
    
    def add(self, rule):
        self._rules.append(rule)
    
    @contextlib.contextmanager
    def new(self):
        r = Rule()
        yield r
        self.add(r)
    
    #def __iter__(self):
    #    yield from self.filter()
    
    def _check_filter_req(self, rule, **kwargs):
        for k, v in kwargs.items():
            if v is None:
                continue
            
            lv = getattr(i, k)
            if isinstance(lv, [list, dict]):
                if v not in lv:
                     return False
            else:
                if v != lv:
                    return False
        
        return True
    
    def filter(self, ipv4=None, ipv6=None, has_tag=None, has_tag_with_value=None):
        rs = sorted(self._rules, lambda a,b: cmp(a._group, b._group))
        
        for i in rs:
            
            if ipv4 is not None and ipv4 != i._ipv4:
                continue
            if ipv6 is not None and ipv6 != i._ipv6:
                continue
            if has_tag is not None and has_tag not in i._tags:
                continue
            if has_tag_with_value is not None:
                for k,v in has_tag_with_value.items():
                    if not i._tags.has(k):
                        break
                    if isinstance(v, list):
                        if v not in i._tags[k]:
                            break
                    else:
                        if v != i._tags[k]:
                            break
                else:
                    continue
            
            yield i
    
    __iter__ = filter

class DockerHandler(object):
    
    client = None
    
    _networks = None
    _containers = None
    
    def __init__(self):
        super(DockerHandler, self).__init__()
        self.logger = logging.getLogger(self.__class__.__name__)
        
        self._rules = RuleSet()
    
    def setup(self):
        try:
            client = docker.from_env()
            client.ping()
        except Exception:
            raise ConnectionException('Error communicating with docker.')
        
        self.logger.info("Connected to docker")
        self.client = client
        
        self.load()
    
    def _get_networks(self):
        if self._networks is None:
            networks = []
            for data in self.client.networks():
                n = NetworkConfig(data)
                networks.append((n.name, n))
            
            networks.sort(key=lambda x:x[1].created_at, reverse=True)
            self._networks = OrderedDict(networks)
        return self._networks
    
    def _get_containers(self):
        if self._containers is None:
            containers = []
            for n in self.client.containers():
                cfg = ContainerConfig(n)
                containers.append((cfg.id, cfg))
            containers.sort(key=lambda x:x[1].created_at, reverse=True)
            self._containers = OrderedDict(containers)
        return self._containers
    
    def _get_ip_conf_for_container(self, container):
        networks = self._get_networks()
        
        ip4_conf = ip6_conf = None
        for i in filter(lambda x:networks[x["network_name"]].is_bridge, container.ip_addresses):
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
            
            ip_conf = networks["docker_gwbridge"].containers.get(container.id)
            if ip_conf:
                if ip_conf["ipv6"]:
                    ip6_conf = ip_conf
                if ip_conf["ipv4"]:
                    ip4_conf = ip_conf
        
        return ip4_conf, ip6_conf
    
    def add_network_rules(self, network):
        if not network.is_bridge:
            return
        
        with self._rules.new() as r:
            r.rule("nat", "POSTROUTING", "-o %s -m addrtype --src-type LOCAL -j MASQUERADE" % network.iface)
            r.group(RuleSet.GROUP_NETWORK).ipv4().tags(network=network.id)
            r.ipv6(network.uses_ipv6)
            
        if network.nat:
            grouped_subnets = [["ipv4", network.ip4_subnets], ["ipv6", network.ip6_subnets]]
            for ip_type, subnets in grouped_subnets:
                for subnet in subnets:
                    with self._rules.new() as r:
                        r.rule("nat", "POSTROUTING", "-s %s ! -o %s -j MASQUERADE" % (subnet, network.iface))
                        r.group(RuleSet.GROUP_NETWORK).tags(network=network.id)
                        r.ip_type(ip_type)
        
        with self._rules.new() as r:
            r.rule("filter", "FORWARD", "-o {iface} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT".format(iface = network.iface))
            r.group(RuleSet.GROUP_NETWORK).ipv4().tags(network=network.id)
            r.ipv6(network.uses_ipv6)
        
        with self._rules.new() as r:
            r.rule("filter", "FORWARD", "-o {iface} -j DOCKER".format(iface = network.iface))
            r.group(RuleSet.GROUP_NETWORK).ipv4().tags(network=network.id)
            r.ipv6(network.uses_ipv6)
        
        with self._rules.new() as r:
            r.rule("filter", "FORWARD", "-i {iface} ! -o {iface} -j ACCEPT".format(iface = network.iface))
            r.group(RuleSet.GROUP_NETWORK).ipv4().tags(network=network.id)
            r.ipv6(network.uses_ipv6)
        
        with self._rules.new() as r:
            r.rule("filter", "FORWARD", "-i {iface} -o {iface} -j {action}".format(iface = network.iface, action="ACCEPT" if network.icc else "DROP"))
            r.group(RuleSet.GROUP_NETWORK).ipv4().tags(network=network.id)
            r.ipv6(network.uses_ipv6)
        
        for dst in self._get_networks().values():
            if not dst.is_bridge or dst is network:
                continue
        
            with self._rules.new() as r:
                r.rule("filter", "DOCKER-ISOLATION", "-i {src} -o {dst} -j DROP".format(src=network.iface, dst=dst.iface))
                r.group(RuleSet.GROUP_NETWORK).tags(network=(network.id, dst.id))
                r.ipv4()
                
                # don't add ipv6 rules to non-ipv6 aware networks
                r.ipv6(network.uses_ipv6 and dst.uses_ipv6)
    
    def add_container_rules(self, container):
        ip4_conf, ip6_conf = self._get_ip_conf_for_container(container)
        
        #TODO: check udp
        if ip4_conf or ip6_conf:
            grouped_ips = [["ipv4", ip4_conf], ["ipv6", ip6_conf]]
            for p in container.ports:
                for ip_type, ip_conf in grouped_ips:
                    if ip_conf is None:
                        continue
                    
                    addr = ip_conf[ip_type].addr
                    if ip_type == 'ipv4':
                        prefix = "32"
                        addr_escaped = addr
                    else:
                        prefix = '128'
                        addr_escaped = "[%s]" % addr 
                    
                    with self._rules.new() as r:
                        r.rule("nat", "POSTROUTING", "-s {ip}/{prefix} -d {ip}/{prefix} -p {protocol} -m {protocol} --dport {port} -j MASQUERADE".format(
                            ip = addr,
                            protocol = p.protocol,
                            port = p.private_port,
                            prefix = prefix
                        ))
                        r.group(RuleSet.GROUP_CONTAINER).tags(container=container.id)
                        r.ip_type(ip_type)
                    
                    with self._rules.new() as r:
                        r.rule("nat", "DOCKER", "-p {protocol} -m {protocol} --dport {port} -j DNAT --to-destination {ip}:{private_port}".format(
                            ip = addr_escaped,
                            protocol = p.protocol,
                            private_port = p.private_port,
                            port = p.port
                        ))
                        r.group(RuleSet.GROUP_CONTAINER).tags(container=container.id).ip_type(ip_type)
                    
                    networks = self._get_networks()
                    
                    with self._rules.new() as r:
                        r.rule("filter", "DOCKER", "-d {ip}/{prefix} ! -i {iface} -o {iface} -p {protocol} -m {protocol} --dport {private_port} -j ACCEPT".format(
                            ip = addr,
                            iface = networks[ip_conf["network_name"]].iface,
                            protocol = p.protocol,
                            private_port = p.private_port,
                            prefix = prefix
                        ))
                        r.group(RuleSet.GROUP_CONTAINER).tags(container=container.id).ip_type(ip_type)
    
    def load(self):
        
        for n in self._get_networks().values():
            self.add_network_rules(n)
        
        # for forwarding, docker always uses address from sorted list of bridge network interfaces
        for c in self._get_containers().values():
            self.add_container_rules(c)
                    
        # https://docs.docker.com/engine/userguide/networking/default_network/ipv6/#how-ipv6-works-on-docker
        # TODO: info about ip6 forward sysctl in docs
        
        for r in self._rules.filter():
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
    