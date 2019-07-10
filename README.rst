========
g-docker
========

Configures Docker daemon and allows running containers as system services.

The main target of this module is running containerized apps as system services
when not using cluster supervisor (Docker Swarm, Kubernetes, ...).

----------------
Helpful features
----------------

- containers can be reloaded upon managed configuration changes - no restarting
- persistent container data stored on managed LVM volumes
- binding specific folders to container
- manageable firewall - automatic rules created by Docker are accounted for by
  Puppet, you can safely purge unmanaged firewall rules
- pluggable storage and firewall modules

-----
Usage
-----

Setup
=====

Remember to enable and configure choosen firewall and storage driver.

.. code-block:: puppet

   include ::g_docker::firewall::native
   include ::g_docker::storage::overlay2

   class { ::g_docker: }

Creating containers:
====================

Hiera:

.. code-block:: yaml

   g_docker::instances:
     example:
       image: example:latest
       env:
         MY_ENV: "some env"
       volumes:
         data:
           size: 30G
           binds:
             home:
               path: /data
               readonly: false
               user: 1000
               group: 1000
               mode: a=rx,u+w




Runtime configs and reloading
=============================

You can create small configuration files with puppet and mount it inside
containers.

Hiera:

.. code-block:: yaml

   g_docker::instances:
     example:
       # ...
       runtime_configs:
         pupppetizer:
           target: /var/opt/puppetizer/hiera
           configs:
             "runtime.yaml":
               reload: true
               source: puppet:///modules/profile/proxy.yaml

or Puppet DSL:

.. code-block:: puppet

   g_docker::run { 'example-1':
     ensure => present,
     image => 'example:latest',
     runtime_configs => {
       'puppetizer' => {
         'target' => '/var/opt/puppetizer/hiera',
         'configs' => {
           'runtime.yaml' => {
             'reload' => true,
             'source' => 'puppet:///modules/profile/proxy.yaml',
           },
         },
       },
     },
   }


Following example works identically to previous one:

.. code-block:: puppet

   g_docker::run { 'example-1':
     ensure => present,
     image => 'example:latest',
     runtime_configs => {
       'puppetizer' => {
         'target' => '/var/opt/puppetizer/hiera',
         },
       },
     },
   }

   g_docker::runtime_config::config { 'example':
     container => 'example-1',
     group     => 'puppetizer',
     filename  => 'runtime.yaml',
     reload    => true,
     source    => 'puppet:///modules/profile/proxy.yaml',
   }
