#ANDES Lab - University of California, Merced
#Author: UCM ANDES Lab
#$Author: abeltran2 $
#$LastChangedDate: 2014-08-31 16:06:26 -0700 (Sun, 31 Aug 2014) $
#! /usr/bin/python
import sys
from TOSSIM import *
from CommandMsg import *

class TestSim:
    # COMMAND TYPES
    CMD_PING = 0
    CMD_NEIGHBOR_DUMP = 1
    CMD_ROUTE_DUMP=3
    CMD_TEST_CLIENT = 4
    CMD_TEST_SERVER = 5
    CMD_TEST_CLOSE = 7
    CMD_APP_SERVER = 10
    CMD_APP_CLIENT = 11
    CMD_MESSAGE = 12
    CMD_WHISPER = 13
    CMD_LIST_USERS = 14
    
    # CHANNELS - see includes/channels.h
    COMMAND_CHANNEL="command";
    GENERAL_CHANNEL="general";

    # Project 1
    NEIGHBOR_CHANNEL="neighbor";
    FLOODING_CHANNEL="flooding";

    # Project 2
    ROUTING_CHANNEL="routing";

    # Project 3
    TRANSPORT_CHANNEL="transport";

    # Personal Debuggin Channels for some of the additional models implemented.
    HASHMAP_CHANNEL="hashmap";

    # Initialize Vars
    numMote=0

    def __init__(self):
        self.t = Tossim([])
        self.r = self.t.radio()

        #Create a Command Packet
        self.msg = CommandMsg()
        self.pkt = self.t.newPacket()
        self.pkt.setType(self.msg.get_amType())

    # Load a topo file and use it.
    def loadTopo(self, topoFile):
        print 'Creating Topo!'
        # Read topology file.
        topoFile = 'topo/'+topoFile
        f = open(topoFile, "r")
        self.numMote = int(f.readline());
        print 'Number of Motes', self.numMote
        for line in f:
            s = line.split()
            if s:
                print " ", s[0], " ", s[1], " ", s[2];
                self.r.add(int(s[0]), int(s[1]), float(s[2]))

    # Load a noise file and apply it.
    def loadNoise(self, noiseFile):
        if self.numMote == 0:
            print "Create a topo first"
            return;

        # Get and Create a Noise Model
        noiseFile = 'noise/'+noiseFile;
        noise = open(noiseFile, "r")
        for line in noise:
            str1 = line.strip()
            if str1:
                val = int(str1)
            for i in range(1, self.numMote+1):
                self.t.getNode(i).addNoiseTraceReading(val)

        for i in range(1, self.numMote+1):
            print "Creating noise model for ",i;
            self.t.getNode(i).createNoiseModel()

    def bootNode(self, nodeID):
        if self.numMote == 0:
            print "Create a topo first"
            return;
        self.t.getNode(nodeID).bootAtTime(1333*nodeID);

    def bootAll(self):
        i=0;
        for i in range(1, self.numMote+1):
            self.bootNode(i);

    def moteOff(self, nodeID):
        self.t.getNode(nodeID).turnOff();

    def moteOn(self, nodeID):
        self.t.getNode(nodeID).turnOn();

    def run(self, ticks):
        for i in range(ticks):
            self.t.runNextEvent()

    # Rough run time. tickPerSecond does not work.
    def runTime(self, amount):
        self.run(amount*1000)

    # Generic Command
    def sendCMD(self, ID, dest, payloadStr):
        self.msg.set_dest(dest);
        self.msg.set_id(ID);
        self.msg.setString_payload(payloadStr)
        

        self.pkt.setData(self.msg.data)
        self.pkt.setDestination(dest)
        self.pkt.deliver(dest, self.t.time()+5)
       

    def ping(self, source, dest, msg):
        self.sendCMD(self.CMD_PING, source, "{0}{1}".format(chr(dest),msg));

    def neighborDMP(self, destination):
        self.sendCMD(self.CMD_NEIGHBOR_DUMP, destination, "neighbor command");

    def routeDMP(self, destination):
        self.sendCMD(self.CMD_ROUTE_DUMP, destination, "routing command");

    def addChannel(self, channelName, out=sys.stdout):
        print 'Adding Channel', channelName;
        self.t.addChannel(channelName, out);
        
    def TestServer(self, address, port):
        self.sendCMD(self.CMD_TEST_SERVER, address, chr(port));
        
    def TestClient(self, address, sourcePort, destPort, dest, bufflen):
        self.sendCMD(self.CMD_TEST_CLIENT, address, "{0}{1}{2}{3}".format(chr(sourcePort), chr(destPort), chr(dest), chr(bufflen)));
   # event void CommandHandler.TestClose(uint16_t dest, uint16_t destPort)
    def TestClose(self,address, dest, destPort): 
        self.sendCMD(self.CMD_TEST_CLOSE, address, "{0}{1}".format(chr(dest), chr(destPort)));
        
    def AppServer(self, address):
        self.sendCMD(self.CMD_APP_SERVER, address, "app server command");
        
    def AppClient(self, address, username):
        self.sendCMD(self.CMD_APP_CLIENT, address, "{0}".format(username));
    
    
def main():
    s = TestSim();
    s.runTime(20);
    #s.loadTopo("long_line.topo");
    #s.loadTopo("RingTopology.topo");
    #s.loadTopo("pizza.topo");
    s.loadTopo("circle.topo");
    
    s.loadNoise("no_noise.txt");
    #s.loadNoise("meyer-heavy.txt");
    
    s.bootAll();
    s.addChannel(s.COMMAND_CHANNEL);
    s.addChannel(s.GENERAL_CHANNEL);
    #s.addChannel(s.NEIGHBOR_CHANNEL);
    #s.addChannel(s.FLOODING_CHANNEL);
    #s.addChannel(s.ROUTING_CHANNEL);
    s.addChannel(s.TRANSPORT_CHANNEL);
    
    s.runTime(100);
    s.ping(1, 2, "Hello, World");
    s.runTime(100);
    s.ping(2, 1, "Hello, World");
    s.runTime(100);
    s.ping(3, 2, "Hello, World");
    s.runTime(100);
    #s.ping(9, 10, "Hello, World");
    #s.runTime(100);
    
    #s.TestServer(1, 80);
    s.AppServer(1);
    
    s.runTime(15);
    
    s.AppClient(19, "jeff\r\n");
    #s.TestClient(2, 50, 80, 1, 255);
    
    s.runTime(150);
    
    s.AppClient(2, "nimitt\r\n");
    
    #s.TestClose(2, 1, 80);
    
    s.runTime(15)
    #s.neighborDMP(3);
    #i=0;
    #for i in range(1, s.numMote+1):
    #        s.neighborDMP(i);

if __name__ == '__main__':
    main()
