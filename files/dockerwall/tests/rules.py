import unittest

class TestStringMethods(unittest.TestCase):

    def test_auto_block_removal(self):
        r = RuleSet()
        
        rules = [
            Rule(
                ip_type = IpvType.ip4,
                place = Rule.PLACE_FILTER_ISOLATION,
                data = "asd",
                group = Rule.GROUP_CONTAINER
            ).set_tags(a=1)
        ]
        r.set_block("isolation:container_id", rules)
        
        r.remove_tagged("a", 1)
        
        self.assertEqual(len(r._blocks), 0, "Empty blocks are deleted when all rules are removed by tag")
