import docker

class ConnectionException(Exception):
    pass

class DockerClient(object):
    def __init__(self):
        super(DockerClient, self).__init__()
    
    @property
    def api_v1(self):
        return docker.version.split(".")[0] == "1"
    
    def connect(self):
        try:
            client = docker.from_env()
            client.ping()
        except Exception:
            raise ConnectionException('Error communicating with docker.')
        
        self.client = client
    
    def get_networks(self):
        if self.api_v1:
            for i in self.client.networks():
                yield i
        else:
            for i in self.client.networks.list():
                yield i.attrs
    
    def get_containers(self):
        if self.api_v1:
            for i in self.client.containers():
                yield i
        else:
            for i in self.client.containers.list():
                yield i.attrs
    
    def get_container(self, id):
        if self.api_v1:
            return self.client.containers(filters={"id":id})[0]
        else:
            return self.client.containers.get(id).attrs
    
    def get_network(self, id):
        if self.api_v1:
            return self.client.networks(ids=[id])[0]
        else:
            return self.client.networks.get(id).attrs
    
    def get_network_by_name(self, name):
        try:
            if self.api_v1:
                return self.client.networks(names=[name])[0]
            else:
                return self.client.networks.list(names=[name])[0].attrs
        except IndexError:
            pass
    
    def events(self):
        return self.client.events(decode=True)