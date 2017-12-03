# -*- coding: utf-8 -*-

import logging
from collections import OrderedDict

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
