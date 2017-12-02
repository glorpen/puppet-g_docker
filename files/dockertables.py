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
import copy
import subprocess
import argparse

from dockerwall.rules import *

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
    
    DRIVER_BRIDGE = 'bridge'
    DRIVER_OVERLAY = 'overlay'
    DRIVER_NULL = 'null'
    DRIVER_HOST = 'host'
    
    def __init__(self, node):
        super(NetworkConfig, self).__init__()
        self._read(node)
    
    def _read(self, node):
        self.name = node["Name"]
        self.created_at = node["Created"]
        self.uses_ipv6 = node["EnableIPv6"]
        self.is_ingress = node['Ingress']
        self.driver = node["Driver"]
        self.id = node["Id"]
        self.attachable = node['Attachable']
        
        self.short_id = self.id[:12]
        self.is_bridge = self.driver == self.DRIVER_BRIDGE
        self.is_overlay = self.driver == self.DRIVER_OVERLAY
        
        self.is_default = False
        self.icc = self.nat = None
        if self.is_bridge:
            self.nat = self.get_bool_option(node, "com.docker.network.bridge.enable_ip_masquerade", True)
            self.icc = self.get_bool_option(node, "com.docker.network.bridge.enable_icc", True)
            self.is_default = self.get_bool_option(node, "com.docker.network.bridge.default_bridge", False)
        
        self.subnets = tuple(c["Subnet"] for c in node["IPAM"]["Config"])
        
        self.iface = self._read_iface(node)
        self.containers = self._read_containers(node)

    def get_option(self, node, name, default=None):
        if name in node['Options']:
            return node['Options'][name]
        return default
    
    def get_bool_option(self, node, name, default=None):
        return self.get_option(node, name, default) in ("true", True)
    
    def _read_iface(self, node):
        if self.is_bridge:
            return self.get_option(node, "com.docker.network.bridge.name", "br-%s" % self.short_id)
        elif not self.attachable:
            return None
        
        raise Exception("Not implemented")
    
    def _read_containers(self, node):
        ret = OrderedDict()
        for k,c in node["Containers"].items():
            ret[k] = ContainerNetworkConfig(
                container_id = k,
                network_id = self.id,
                ipv4 = IPAddress(c["IPv4Address"]) if c["IPv4Address"] else None,
                ipv6 = IPAddress(c["IPv6Address"]) if c["IPv6Address"] else None
            )
        return ret
    
    @property
    def ip4_subnets(self):
        return [i for i in self.subnets if ":" not in i]
    
    @property
    def ip6_subnets(self):
        return [i for i in self.subnets if ":" in i]
    

class PortConfig(object):
    def __init__(self, proto, port, private_port, ip=None):
        super(PortConfig, self).__init__()
        
        self.protocol = proto
        self.port = port
        self.private_port = private_port
        self.ip = None if ip == '0.0.0.0' else ip
    
    def __repr__(self):
        return "%s:%d:%s" % (self.ip, self.port, self.protocol)

class ContainerNetworkConfig(object):
    def __init__(self, container_id, network_id, ipv4, ipv6):
        super(ContainerNetworkConfig, self).__init__()
        
        self.ipv4 = ipv4
        self.ipv6 = ipv6
        self.network_id = network_id
        self.container_id = container_id

class ContainerConfig(object):
    def __init__(self, node):
        super(ContainerConfig, self).__init__()
        
        self._read(node)
    
    def _read(self, node):
        self.created_at = node["Created"]
        self.id = node["Id"]
        self.ports = tuple(PortConfig(i['Type'], i['PublicPort'], i['PrivatePort'], i['IP']) for i in node["Ports"])
        self.networks = self._read_networks(node)
    
    def _read_networks(self, node):
        ret = OrderedDict()
        for name, conf in node["NetworkSettings"]["Networks"].items():
            
            # skip invalid entries
            # happens when there is not default bridge given and no other networks are used in container
            if not conf["NetworkID"]:
                continue
            
            ret[conf["NetworkID"]] = ContainerNetworkConfig(
                container_id = self.id,
                network_id = conf["NetworkID"],
                ipv4 = IPAddress(conf["IPAddress"], conf["IPPrefixLen"]) if conf["IPAddress"] else None,
                ipv6 = IPAddress(conf["GlobalIPv6Address"], conf["GlobalIPv6PrefixLen"]) if conf["GlobalIPv6Address"] else None
            )
        return ret

def _filter_rules(rules, ipv4=None, ipv6=None, has_tag=None, has_tag_value=None, f=None):
    for item in rules:
        
        if f is None:
            i = item
        else:
            i = f(item)
        
        if ipv4 is not None and ipv4 != i._ipv4:
            continue
        if ipv6 is not None and ipv6 != i._ipv6:
            continue
        if has_tag is not None:
            if has_tag not in i._tags:
                continue
            if has_tag_value is not None:
                v = i._tags[has_tag]
                if isinstance(v, (list, tuple)):
                    if has_tag_value not in v:
                        continue
                else:
                    if has_tag_value != v:
                        continue
        
        yield i

class Iptables(object):
    def __init__(self, ip=IpType.ip4, pretend=False):
        super(Iptables, self).__init__()
        self.logger = logging.getLogger(self.__class__.__name__)
        self.pretend = pretend
        self._bin = "iptables" if ip == IpType.ip4 else "ip6tables"
    
    def append(self, rule):
        self._cmd("-t %s -A %s %s" % (rule.table, rule.chain, rule.data))
    
    def insert(self, pos, rule):
        self._cmd("-t %s -I %s %d %s" % (rule.table, rule.chain, pos, rule.data))
    
    def delete(self, table, chain, pos):
        self._cmd("-t %s -D %s %d" % (table, chain, pos))
    
    def flush(self, place=None, table=None, chain=None):
        if place:
            table = place.table
            chain = place.chain
        self._cmd("-t %s -F %s" % (table, chain))
    
    def _cmd(self, args, ipv6=False, ipv4=False):
        cmd = "%s %s" % (self._bin, args)
        if self.pretend:
            self.logger.debug("Would run %r", cmd)
        else:
            self.logger.debug("Running %r", cmd)
            subprocess.check_call(cmd, shell=True)
        

class DockerHandler(object):
    
    client = None
    
    """ When new container is added, or its networks are changed, we need to update
    gwbridge just in case it is used by it. Data will be reloaded from API only
    if container is using gwbridge."""
    _gwbridge_needs_updating = False
    
    def __init__(self, pretend=False):
        super(DockerHandler, self).__init__()
        self.logger = logging.getLogger(self.__class__.__name__)
        
        self.pretend = pretend
        self._rules = RuleSet()
        
        self._networks = OrderedDict()
        self._containers = OrderedDict()
    
    def setup(self):
        try:
            client = docker.from_env()
            client.ping()
        except Exception:
            raise ConnectionException('Error communicating with docker.')
        
        self.logger.info("Connected to docker")
        self.client = client
        
        self.load()
    
    def fetch_networks(self):
        networks = []
        for data in self.client.networks():
            n = NetworkConfig(data)
            networks.append(n)
        
        networks.sort(key=lambda x:x.created_at, reverse=True)
        return networks
        
    def fetch_containers(self):
        containers = []
        for n in self.client.containers():
            cfg = ContainerConfig(n)
            containers.append(cfg)
        containers.sort(key=lambda x:x.created_at, reverse=True)
        return containers
    
    def get_gwbridge_network(self):
        if self._gwbridge_needs_updating:
            cfg = NetworkConfig(self.client.networks(names=["docker_gwbridge"])[0])
            self._networks[cfg.id] = cfg
        
        for n in self._networks.values():
            if n.name == "docker_gwbridge":
                return n
    
    def _get_ip_conf_for_container(self, container):
        # for forwarding, docker always uses address from sorted list of bridge network interfaces
        
        ip4_conf = ip6_conf = None
        for i in filter(lambda x:self._networks[x.network_id].is_bridge, container.networks.values()):
            if not ip4_conf and i.ipv4:
                ip4_conf = i
            if not ip6_conf and i.ipv6:
                ip6_conf = i
                # if both ipv4 and ipv6 addresses are found, Docker uses that network
                if i.ipv4:
                    ip4_conf = i
            
            if ip6_conf and ip4_conf:
                break
        else:
            # when there is no bridge network and only overlay is available,
            # docker implictly uses docker_gwbridge (it is not reported in container inspect data)
            # so we have to find its ip address in network data
            
            # TODO: check ipv6 failover on docker_gwbridge
            
            gwbridge = self.get_gwbridge_network()
            if gwbridge:
                ip_conf = gwbridge.containers.get(container.id)
                if ip_conf:
                    if ip_conf.ipv6 is not None:
                        ip6_conf = ip_conf
                    if ip_conf.ipv4 is not None:
                        ip4_conf = ip_conf
        
        return ip4_conf, ip6_conf
    
    def add_network_rules(self, network):
        # only bridge networks are supported
        if not network.is_bridge:
            return
        
        with self._rules.with_block(network=network.id) as rules:
            with rules.new() as r:
                r.rule(r.PLACE_NAT_POSTROUTING, "-o %s -m addrtype --src-type LOCAL -j MASQUERADE" % network.iface)
                r.group(r.GROUP_NETWORK).ipv4()
                r.ipv6(network.uses_ipv6)
            
            #FIXME: when docker is started with iptables=false, ip-masq is always false too, so default bridge has no nat
            if network.nat or network.is_default:
                grouped_subnets = [[IpType.ip4, network.ip4_subnets], [IpType.ip6, network.ip6_subnets]]
                for ip_type, subnets in grouped_subnets:
                    for subnet in subnets:
                        with rules.new() as r:
                            r.rule(r.PLACE_NAT_POSTROUTING, "-s %s ! -o %s -j MASQUERADE" % (subnet, network.iface))
                            r.group(r.GROUP_NETWORK)
                            r.ip_type(ip_type)
            
            with rules.new() as r:
                r.rule(r.PLACE_FILTER_FORWARD, "-o {iface} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT".format(iface = network.iface))
                r.group(r.GROUP_NETWORK).ipv4()
                r.ipv6(network.uses_ipv6)
            
            with rules.new() as r:
                r.rule(r.PLACE_FILTER_FORWARD, "-o {iface} -j DOCKER".format(iface = network.iface))
                r.group(r.GROUP_NETWORK).ipv4()
                r.ipv6(network.uses_ipv6)
            
            with rules.new() as r:
                r.rule(r.PLACE_FILTER_FORWARD, "-i {iface} ! -o {iface} -j ACCEPT".format(iface = network.iface))
                r.group(r.GROUP_NETWORK).ipv4()
                r.ipv6(network.uses_ipv6)
            
            with rules.new() as r:
                r.rule(r.PLACE_FILTER_FORWARD, "-i {iface} -o {iface} -j {action}".format(iface = network.iface, action="ACCEPT" if network.icc else "DROP"))
                r.group(r.GROUP_NETWORK).ipv4()
                r.ipv6(network.uses_ipv6)
        
        '''
        Networks are added in linear fashion by add_network method so n-th network will generate all related rules.
        When network is deleted, it will remove rules that possibly were not generated by it, but when added again, they will be generated.
        Updating rules is not supported as it would created duplicates (in Docker, network config cannot be changed once created, so it is ok). 
        '''
        with self._rules.with_block(isolation_network=network.id) as rules:
            for other in self._networks.values():
                if other is network or not other.is_bridge:
                    continue
                
                for src, dst in [[network, other], [other, network]]:
                    with rules.new() as r:
                        r.rule(r.PLACE_FILTER_ISOLATION, "-i {src} -o {dst} -j DROP".format(src=src.iface, dst=dst.iface))
                        r.group(r.GROUP_NETWORK).tags(network=(src.id, dst.id))
                        r.ipv4()
                        
                        # don't add ipv6 rules to non-ipv6 aware networks
                        r.ipv6(src.uses_ipv6 and dst.uses_ipv6)
    
    def set_container_rules(self, container):
        ip4_conf, ip6_conf = self._get_ip_conf_for_container(container)
        
        # set block event if its empty eg. container lost all networks
        with self._rules.with_block(container=container.id) as rules:
        
        #TODO: check if udp mode is working
            if ip4_conf or ip6_conf:
                grouped_ips = [["ipv4", ip4_conf], ["ipv6", ip6_conf]]
                
                for p in container.ports:
                    for ip_type, ip_conf in grouped_ips:
                        if ip_conf is None:
                            continue
                        
                        addr = getattr(ip_conf, ip_type).addr
                        if ip_type == 'ipv4':
                            prefix = "32"
                            addr_escaped = addr
                        else:
                            prefix = '128'
                            addr_escaped = "[%s]" % addr 
                        
                        with rules.new() as r:
                            r.rule(r.PLACE_NAT_POSTROUTING, "-s {ip}/{prefix} -d {ip}/{prefix} -p {protocol} -m {protocol} --dport {port} -j MASQUERADE".format(
                                ip = addr,
                                protocol = p.protocol,
                                port = p.private_port,
                                prefix = prefix
                            ))
                            r.group(r.GROUP_CONTAINER)
                            r.ip_type(ip_type)
                        
                        with rules.new() as r:
                            r.rule(r.PLACE_NAT_DOCKER, "-p {protocol} -m {protocol} --dport {port} -j DNAT --to-destination {ip}:{private_port}".format(
                                ip = addr_escaped,
                                protocol = p.protocol,
                                private_port = p.private_port,
                                port = p.port
                            ))
                            r.group(r.GROUP_CONTAINER).ip_type(ip_type)
                        
                        with rules.new() as r:
                            r.rule(r.PLACE_FILTER_DOCKER, "-d {ip}/{prefix} ! -i {iface} -o {iface} -p {protocol} -m {protocol} --dport {private_port} -j ACCEPT".format(
                                ip = addr,
                                iface = self._networks[ip_conf.network_id].iface,
                                protocol = p.protocol,
                                private_port = p.private_port,
                                prefix = prefix
                            ))
                            r.group(r.GROUP_CONTAINER).ip_type(ip_type)
    
    def add_network(self, network):
        self._networks[network.id] = network
        self.add_network_rules(network)
    
    def _apply_changes(self, diff):
        for ip in IpType.list():
            iptables = Iptables(ip, pretend=self.pretend)
            
            for pos, r in reversed(list(diff.get_removed_rules(ip))):
                iptables.delete(r.table, r.chain, pos)
            
            for pos, r in diff.get_added_rules(ip):
                iptables.insert(pos, r)
            
    def add_container(self, container):
        self._containers[container.id] = container
        self.set_container_rules(container)
    
    def update_container(self, container):
        self._containers[container.id] = container
        
        diff = self._rules.diff()
        with diff:
            self.set_container_rules(container)
        
        self._apply_changes(diff)
        
    def load(self):
        
        with self._rules.with_block("returns") as rules:
            with rules.new() as r:
                r.rule(r.PLACE_FILTER_ISOLATION, "-j RETURN")
                r.group(r.GROUP_LAST).ip_any()
        
            with rules.new() as r:
                r.rule(r.PLACE_NAT_POSTROUTING, "-j RETURN")
                r.group(r.GROUP_LAST).ip_any()
            
            with rules.new() as r:
                r.rule(r.PLACE_FILTER_FORWARD, "-j RETURN")
                r.group(r.GROUP_LAST).ip_any()
        
        for n in self.fetch_networks():
            self.add_network(n)
        
        for c in self.fetch_containers():
            self.add_container(c)
        
        # https://docs.docker.com/engine/userguide/networking/default_network/ipv6/#how-ipv6-works-on-docker
        # TODO: info about ip6 forward sysctl in docs
        
        for ip in IpType.list():
            iptables = Iptables(ip, pretend=self.pretend)
            
            iptables.flush(RuleDefinition.PLACE_NAT_DOCKER)
            iptables.flush(RuleDefinition.PLACE_NAT_POSTROUTING)
            iptables.flush(RuleDefinition.PLACE_FILTER_DOCKER)
            iptables.flush(RuleDefinition.PLACE_FILTER_FORWARD)
            iptables.flush(RuleDefinition.PLACE_FILTER_ISOLATION)
            
            for r in self._rules.get_rules(ip):
                iptables.append(r)
    
    def handle_event(self, event):
        
        # TODO: when container is stopping there is no need to update ContainerConfig on network disconnect event since it will be deleted
        
        """As for `_gwbridge_needs_updating`, docker does not inform about connect/disconnects to gwbridge network
        so we have to handle it."""
        
        d = self._rules.diff()
        with d:
            if event["Type"] == "container":
                container_id = event["Actor"]['ID']
                
                if event["Action"] == 'start':
                    self.logger.info("Adding container %r", container_id)
                    self._gwbridge_needs_updating = True
                    container_config = ContainerConfig(self.client.containers(filters={"id":container_id})[0])
                    self.add_container(container_config)
                
                if event["Action"] == 'stop':
                    # no need to update gwbridge since IP addr stays the same for other containers
                    self.logger.info("Removing container %r", container_id)
                    del self._containers[container_id]
                    self._rules.remove_block(container=container_id)
                    
                # no swarm support, so no published ports changing
            
            if event["Type"] == "network":
                network_id = event["Actor"]['ID']
                """ container start/stop triggers it too """
                if event["Action"] in ("connect", "disconnect"):
                    # currently there is no need to update config for changed network, only gwbridge matters
                    self._gwbridge_needs_updating = True
                    
                    container_id = event["Actor"]["Attributes"]["container"]
                    # if container is just starting, it will not be listed in api.containers()
                    # so handle it only if already known
                    if container_id in self._containers:
                        container = ContainerConfig(self.client.containers(filters={"id":container_id})[0])
                        self.update_container(container)
                
                if event["Action"] == "create":
                    self.logger.info("Adding network %r", network_id)
                    network_config = NetworkConfig(self.client.networks(ids=[network_id])[0])
                    self.add_network(network_config)
                
                """ happens only when there are no containers attached """
                if event["Action"] == "destroy":
                    self.logger.info("Removing network %r", network_id)
                    
                    del self._networks[network_id]
                    self._rules.remove_block(network=network_id)
                    self._rules.remove_tagged("network", network_id)
                
        
        self._apply_changes(d)
    
    def run(self):
        events = self.client.events(decode=True)
        
        while True:
            try:
                event = next(events)
            except docker.StopException:
                self.logger.info("Exiting")
                return
            except Exception:
                self.logger.info("Docker connection broken - exitting")
                return
            
            self.handle_event(event)

if __name__ == "__main__":
    logging.basicConfig(level=logging.DEBUG)
    parser = argparse.ArgumentParser()
    parser.add_argument('--pretend', '-p', '--noop', help="Don't do anything", action="store_true", default=False)
    
    ns = parser.parse_args()
    
    d = DockerHandler(pretend=ns.pretend)
    d.setup()
    d.run()
    
    #nsenter --net=/var/run/docker/netns/ingress_sbox iptables-save
    # czy na node0 w NS pojawią się wpisy jeśli iptables=false? - tak, dodatkowo też są w zwykłym iptables
    # a co gdy etc będzie zamiast swarm init?
    