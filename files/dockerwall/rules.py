# -*- coding: utf-8 -*-

"""
rules[table:chain:group].set_block(name, [rules])
rules[table:chain:group].add_tagged(rules, tags={"network_id": [a,b]})

ale już ma te opcje Rule(table=, chain=)

rules.set_block(block_name, group, rules)
# tworzy wpisy bloków w odpowiednich tablicach ipv/table/chain/group
rules.remove_block(name)

"""
from __future__ import print_function
from collections import OrderedDict
import contextlib
import copy
import itertools
import re

class IpType(object):
    ip4 = 4
    ip6 = 6
    
    _number = re.compile('([0-9])')
    
    @classmethod
    def list(cls):
        return [cls.ip4, cls.ip6]
    
    @classmethod
    def get_types(cls, ip4, ip6):
        ret = []
        if ip4:
            ret.append(cls.ip4)
        if ip6:
            ret.append(cls.ip6)
        return tuple(ret)
    
    @classmethod
    def as_type(cls, v):
        if not isinstance(v, int):
            m = cls._number.search(str(v))
            if m:
                normalized = int(m.group(1))
        else:
            normalized = v
            
        if normalized in cls.list():
            return normalized
        else:
            raise Exception("IP type not found in %r" % v)

class Rule(object):
    
    ip_type = None
    table = None
    chain = None
    data = None
    group = None
    
    def __init__(self):
        super(Rule, self).__init__()
        self.tags = {}
    
    def __repr__(self):
        return "ip%d -t %s -A %s %s [group:%d]" % (self.ip_type, self.table, self.chain, self.data, self.group) #no tags

class RulePlace(object):
    def __init__(self, table, chain):
        super(RulePlace, self).__init__()
        self.table = table
        self.chain = chain
    
    def __repr__(self):
        return "<RulePlace %s:%s>" % (self.table, self.chain)

class RuleDefinition(object):
    GROUP_NETWORK = 1
    GROUP_CONTAINER = 2
    GROUP_LAST = 9
    
    PLACE_FILTER_FORWARD = RulePlace('filter', 'DOCKER-FORWARD')
    PLACE_NAT_POSTROUTING = RulePlace('nat', 'DOCKER-POSTROUTING')
    PLACE_FILTER_ISOLATION = RulePlace('filter', 'DOCKER-ISOLATION')
    PLACE_NAT_DOCKER = RulePlace('nat', 'DOCKER')
    PLACE_FILTER_DOCKER = RulePlace('filter', 'DOCKER')
    
    _ipv4 = False
    _ipv6 = False
    
    def __init__(self):
        super(RuleDefinition, self).__init__()
        
        self._tags = {}
    
    def rule(self, place, data):
        self._place = place
        self._data = data
    
    def ipv6(self, v=True):
        self._ipv6 = v
        return self
    
    def ipv4(self, v=True):
        self._ipv4 = v
        return self
    
    def ip_any(self):
        return self.ipv4().ipv6()
    
    def ip_type(self, t):
        t = IpType.as_type(t)
        if t == IpType.ip4:
            return self.ipv4()
        if t == IpType.ip6:
            return self.ipv6()
        
        raise Exception("Unknown IpType %r" % t)
    
    def group(self, group):
        self._group = group
        return self
    
    def tags(self, **kwargs):
        self._tags = kwargs
        return self

class RuleGenerator(object):
    
    def __init__(self):
        super(RuleGenerator, self).__init__()
        
        self._definitions = []
    
    @contextlib.contextmanager
    def new(self):
        d = RuleDefinition()
        yield d
        self._definitions.append(d)
    
    def get_rules(self):
        for d in self._definitions:
            tags = copy.copy(d._tags)
            ip_types = IpType.get_types(d._ipv4, d._ipv6)
            for i in ip_types:
                r = Rule()
                r.ip_type = i
                r.table = d._place.table
                r.chain = d._place.chain
                r.data = d._data
                r.group = d._group
                r.tags = tags
                
                yield r
    
class _OrderedRules(OrderedDict):
    def __init__(self, rules):
        super(_OrderedRules, self).__init__((hash(i), i) for i in rules)

class RuleSet(object):
    
    def __init__(self):
        super(RuleSet, self).__init__()
        
        self._blocks = OrderedDict()
    
    def _get_block_name(self, *args, **kwargs):
        if len(args) == 0:
            return ":".join(itertools.chain(*kwargs.items()))
        return str(args[0])
    
    def set_block(self, name, rules):
        self._blocks[name] = _OrderedRules(rules)
    
    def remove_block(self, *args, **kwargs):
        name = self._get_block_name(*args, **kwargs)
        del self._blocks[name]
    
    def get_rules(self, ip_type):
        # block + tagged rules, sorted by group, table, ...
        rules = []
        for i in self._blocks.values():
            for r in i.values():
                if r.ip_type == ip_type:
                    rules.append(r)
        
        rules.sort(key=lambda x: x.group)
        rules.sort(key=lambda x: x.table)
        rules.sort(key=lambda x: x.chain)
        
        return rules
    
    def remove_tagged(self, tag, value):
        # remove block if empty
        for name, ruleset in self._blocks.items():
            for h, rule in ruleset.items():
                is_matched = False
                
                try:
                    remote_value = rule.tags[tag]
                except KeyError:
                    continue
                
                if isinstance(remote_value, (list, tuple)):
                    is_matched = value in remote_value
                else:
                    is_matched = remote_value == value
                
                if is_matched:
                    del ruleset[h]
            
            if len(ruleset) == 0:
                self.remove_block(name)
    
    @contextlib.contextmanager
    def with_block(self, *args, **kwargs):
        """
        Saves rules to named block.
        with_block(block_name="network:123") is equivalent to with_block(network="123")
        """
        
        block_name = self._get_block_name(*args, **kwargs)
        
        r = RuleGenerator()
        yield r
        self.set_block(block_name, r.get_rules())
    
    def diff(self):
        return RuleSetDiff(self)

class RuleSetDiff(object):
    def __init__(self, rule_set):
        super(RuleSetDiff, self).__init__()
        self._rule_set = rule_set
    
    def __enter__(self):
        self._org = self._as_dict(self._rule_set)
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self._current = self._as_dict(self._rule_set)
    
    def _enumerate_by_chain(self, rules, ip_type):
        places = OrderedDict()
        for r in rules[ip_type].values():
            if r.ip_type != ip_type:
                continue
            
            k = "%s:%s" % (r.table, r.chain)
            places[k] = places.get(k, 0) + 1
            
            yield places[k], r
    
    def _as_dict(self, ruleset):
        ret = {}
        for ip in IpType.list():
            hashed_rules = OrderedDict()
            for r in ruleset.get_rules(ip):
                k = repr(r)
                if k in hashed_rules:
                    raise Exception("Duplicated rule %r" % r)
                hashed_rules[k] = r
            ret[ip] = hashed_rules
        return ret
    
    def get_removed_rules(self, ip_type):
        """
        Yields removed rule position in chain and rule.
        """
        removed = set(self._org[ip_type].keys()).difference(self._current[ip_type].keys())
        
        for pos, r in self._enumerate_by_chain(self._org, ip_type):
            if repr(r) in removed:
                yield (pos, r)
    
    def get_added_rules(self, ip_type):
        added = set(self._current[ip_type].keys()).difference(self._org[ip_type].keys())
        
        for pos, r in self._enumerate_by_chain(self._current, ip_type):
            if repr(r) in added:
                yield (pos, r)    
    

"""
r = RuleSet()

rules = [
    Rule(
        ip_type = IpType.ip4,
        place = Rule.PLACE_FILTER_ISOLATION,
        data = "asd",
        group = Rule.GROUP_CONTAINER
    ).set_tags(a=1)
]
r.set_block("isolation:container_id", rules)

print(r.get_rules(IpType.ip4))

diff = RuleSetDiff(r)
with diff:
    r.set_block("isolation:container_id", [
        Rule(
            ip_type = IpType.ip4,
            place = Rule.PLACE_FILTER_ISOLATION,
            data = "asd2",
            group = Rule.GROUP_NETWORK
        ).set_tags(a=1)
    ])
    
    with r.with_block("qasd") as store:
        store.append(Rule(
            ip_type = IpType.ip4,
            place = Rule.PLACE_FILTER_ISOLATION,
            data = "asd3",
            group = Rule.GROUP_NETWORK
        ))

print(list(diff.get_removed_rules(IpType.ip4)))
print(list(diff.get_added_rules(IpType.ip4)))
"""
