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
    
    @property
    def subnets(self):
        return [c["Subnet"] for c in self._node["IPAM"]["Config"]]

class PortConfig(object):
    def __init__(self, proto, port, ip=None):
        super(PortConfig, self).__init__()
        
        self.protocol = proto
        self.port = port
        self.ip = None if ip == '0.0.0.0' else ip
    
    def __repr__(self):
        return "%s:%d:%s" % (self.ip, self.port, self.protocol)

class ContainerConfig(object):
    def __init__(self, node):
        super(ContainerConfig, self).__init__()
        self._node = node
    
    @property
    def id(self):
        return self._node["Id"]
    
    @property
    def ports(self):
        return [PortConfig(i['Type'], i['PublicPort'], i['IP']) for i in self._node["Ports"]]
    
    @property
    def ipv4_address(self):
        print(self._node)
        return self._node["IPAddress"]
    
    @property
    def ipv6_address(self):
        return self._node["GlobalIPv6Address"]

# class ServiceConfig(object):
#     def __init__(self, node):
#         super(ServiceConfig, self).__init__()
#         self._node = node
#     
#     @property
#     def id(self):
#         return self._node["Id"]
#     
#     @property
#     def ports(self):
#         return [PortConfig(i['Protocol'], i['PublishedPort']) for i in self._node["Endpoint"]["Ports"]]

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
    
    def load_containers(self):
        
        networks = sorted([NetworkConfig(n) for n in self.client.networks()], key=lambda x:x.created_at, reverse=True)
        
        nat_rules = []
        
        for n in networks:
            if n.nat:
                if n.name == "docker_gwbridge":
                    nat_rules.append("-A POSTROUTING -o %s -m addrtype --src-type LOCAL -j MASQUERADE" % n.iface)
                for subnet in n.subnets:
                    nat_rules.append("-A POSTROUTING -s %s ! -o %s -j MASQUERADE" % (subnet, n.iface))
        
                #rules.append("-A DOCKER -i %s -j RETURN" % n.iface)
        
        for n in self.client.containers():
            cfg = ContainerConfig(n)
            print(cfg.ipv4_address)
        
#         for n in self.client.services():
#             cfg = ServiceConfig(n)
#             #print(cfg.ports)
        
        rules = nat_rules
        
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
    