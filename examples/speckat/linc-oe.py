#!/usr/bin/env python

from optical import LINCNet, LINCSwitch, LINCLink

from mininet.node import OVSSwitch, RemoteController
from mininet.cli import CLI
from mininet.net import Mininet
from mininet.log import lg, info, error, debug, output

def start(ip="127.0.0.1",port=6633):

    # Set up logging etc.
    lg.setLogLevel('info')
    lg.setLogLevel('output')

    ctrlr = lambda n: RemoteController(n, ip=ip, port=port, inNamespace=False)
    net = LINCNet(switch=OVSSwitch, controller=ctrlr, listenPort=6635)
    c1 = net.addController('c1')

    # Add hosts
    h1 = net.addHost('h1')
    h2 = net.addHost('h2')
    h3 = net.addHost('h3')

    # Add electrical switches
    s1 = net.addSwitch('s1', dpid='00:00:00:00:00:00:00:01')
    s2 = net.addSwitch('s2', dpid='00:00:00:00:00:00:00:02')
    s3 = net.addSwitch('s3', dpid='00:00:00:00:00:00:00:03')


    # Add optical switches
    r1 = net.addSwitch('r1', dpid='00:00:00:00:00:00:00:04', cls=LINCSwitch)
    r2 = net.addSwitch('r2', dpid='00:00:00:00:00:00:00:05', cls=LINCSwitch)
    r3 = net.addSwitch('r3', dpid='00:00:00:00:00:00:00:06', cls=LINCSwitch)
    r4 = net.addSwitch('r4', dpid='00:00:00:00:00:00:00:07', cls=LINCSwitch)

    # Add electrical host-switch links
    net.addLink(h1, s1)
    net.addLink(h2, s2)
    net.addLink(h3, s3)

    # Add optical links
    net.addLink(r1, r4, 1, 1, cls=LINCLink)
    net.addLink(r2, r4, 1, 2, cls=LINCLink)
    net.addLink(r3, r4, 1, 3, cls=LINCLink)

    # Add electrical-optical links
    net.addLink(s1, r1, 2, 2, cls=LINCLink)
    net.addLink(s1, r1, 3, 3, cls=LINCLink)
    net.addLink(s2, r2, 2, 2, cls=LINCLink)
    net.addLink(s3, r3, 2, 2, cls=LINCLink)

    # Start the network and prime other ARP caches
    net.start()
    net.staticArp()

    # Enter CLI mode
    output("Network ready\n")
    output("Press Ctrl-d or type exit to quit\n")
    CLI(net)
    net.stop()

start()
