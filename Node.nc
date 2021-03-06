/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "includes/lspTable.h"
#include "includes/socket.h"
#include "math.h"

// Neighbor structure for Neighbor Discovery.
typedef nx_struct neighbor 
{
	nx_uint16_t Node;
	nx_uint8_t Life;
}neighbor;

//Creates a Map of all the Nodes
typedef struct lspMap
{
	uint8_t cost[20];
}lspMap;

typedef struct chatClient
{
	char username[50];
	bool active;
}chatClient;

// Sequence number of this node.
int seqNum = 1;

// The length of the message being sent.
uint8_t buffLen = 0;

// If fragmentation occurs, this will be the number of messages being sent.
int numMsgs = 1;

// Message checking.
bool ackRcvd[10];
int msgLength[10];
int msgsRcvd = 0;
uint16_t SRCPM;
uint16_t DPM;
uint16_t destinationM;

//Project 4 Var: 
char username[50];

int chatMessage[25];

char dest[50];

chatClient user[20];

module Node
{
	// Main interfaces.
	uses interface Boot;
	uses interface SplitControl as AMControl;
	uses interface Receive;
	uses interface SimpleSend as Sender;
	uses interface CommandHandler;

	// Timers.
	uses interface Timer<TMilli> as Timer1;
	uses interface Timer<TMilli> as lspTimer;
	uses interface Timer<TMilli> as sendTimer;
	uses interface Random as Random;

	// Data Structures.
	uses interface List<neighbor> as NeighborList;
	uses interface List<pack> as SeenPackList;
	uses interface List<pack> as SeenLspPackList;
	
	// Transport Interface.
	uses interface Transport;
}

implementation
{
	pack sendPackage;

	// Checks for printing.
	bool printNodeNeighbors = FALSE;
	bool netChange = FALSE;


	// Prototypes
	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

	// Project 1 functions: Neighbor Discovery.
	void printNeighbors();
	void printNeighborList();
	void neighborDiscovery();
	bool checkPacket(pack Packet);

	// Project 2 functions: Link State.
	void lspNeighborDiscoveryPacket();
	lspMap lspMAP[20];
	int lspSeqNum = 0;
	bool checkSeenLspPacks(pack Packet);
	lspTable confirmedList;
	lspTable tentativeList;
	float cost[20];
	int lastSequenceTracker[20] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
	void printlspMap(lspMap *list);
	void dijkstra();
	int forwardPacketTo(lspTable* list, int dest);
	void printCostList(lspMap *list, uint8_t nodeID);
	float EMA(float prevEMA, float now,float weight);
	void initializeMap(lspMap *Map, int TOS_NODE_ID);
	lspEntry getMinCost(lspTable* Table);

	event void Boot.booted()
	{
		int i;
		call AMControl.start();
		dbg(GENERAL_CHANNEL, "Booted\n");
		
		
		for(i = 0; i < 20; i++)
			user[i].active = FALSE;
		
	}

	event void Timer1.fired()
	{
		neighborDiscovery();
	}

	event void lspTimer.fired()
	{
			lspNeighborDiscoveryPacket(); 
	}

	event void sendTimer.fired()
	{
	//int msgLength[10];
		

	}

	event void AMControl.startDone(error_t err)
	{
		if(err == SUCCESS)
		{
			dbg(GENERAL_CHANNEL, "Radio On\n");
			call Timer1.startPeriodic(100000 + (uint16_t)((call Random.rand16())%200));
			call lspTimer.startPeriodic(100000 + (uint16_t)((call Random.rand16())%200));
		}
		else
		{
			//Retry until successful
			call AMControl.start();
		}
	}

	event void AMControl.stopDone(error_t err){}

	event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len)
	{
		//dbg(GENERAL_CHANNEL, "Packet Received\n");

		// Temporary Variable for use of the size of the list of Neighbors.
		uint16_t size = call NeighborList.size();

		if(len==sizeof(pack))
		{
			pack* myMsg=(pack*) payload;


			// If the message has a TTL of 0, do nothing with it.
			if(myMsg->TTL == 0) {return msg;}
			
			else if(myMsg->protocol == PROTOCOL_TCP_USER && myMsg->dest == TOS_NODE_ID)
			{
				int i = 0;
				
				dbg(TRANSPORT_CHANNEL, "Username received: ");
				
				while(TRUE)
				{
					if(myMsg->payload[i] == '\n')
					{
						user[myMsg->src].username[i] = myMsg->payload[i];
						printf("%c", user[myMsg->src].username[i]);
						i++;
						break;
					}
					else
					{
						user[myMsg->src].username[i] = myMsg->payload[i];
						printf("%c", user[myMsg->src].username[i]);
						i++;
					}
				}
				
				user[myMsg->src].active = TRUE;
				
				return msg;
			}
			
			else if(myMsg->protocol == PROTOCOL_TCP_MSG && myMsg->dest == TOS_NODE_ID)
			{
				pack DATA;
				char chat[25];
				int i = 0;
				
				dbg(TRANSPORT_CHANNEL, "Message received from client: ");
				
				while(TRUE)
				{
					if(user[myMsg->src].username[i] == '\n')
					{
						printf("%c", user[myMsg->src].username[i]);
						i++;
						break;
					}
					else
					{
						printf("%c", user[myMsg->src].username[i]);
						i++;
					}
				}
				
				dbg(TRANSPORT_CHANNEL, "Message: ");
				i = 0;
				while(TRUE)
				{
					if(myMsg->payload[i] == '\n')
					{
						printf("%c", myMsg->payload[i]);
						chat[i] = myMsg->payload[i];
						i++;
						break;
					}
					else
					{
						printf("%c", myMsg->payload[i]);
						chat[i] = myMsg->payload[i];
						i++;
					}
				}	 
				
				dbg(TRANSPORT_CHANNEL, "Message has been received. Sending out to chat clients.\n");
				
				for(i = 0; i < 20; i++)
				{
					if(user[i].active == TRUE)
					{
						DATA.src = TOS_NODE_ID;
						DATA.dest = i;
						DATA.seq = 1;
						DATA.TTL = MAX_TTL;
						DATA.protocol = PROTOCOL_TCP_MSG_CLIENT;

						memcpy(DATA.payload, &chat, (uint8_t) sizeof(chat));

						// Send out the Username.
						call Sender.send(DATA, forwardPacketTo(&confirmedList, i));
					}
				}
				
				return msg;
				
			}
			
			else if(myMsg->protocol == PROTOCOL_TCP_MSG_CLIENT && myMsg->dest == TOS_NODE_ID)
			{
				int i;
				dbg(TRANSPORT_CHANNEL, "Message received from server.\n");
				
				dbg(TRANSPORT_CHANNEL, "Message: ");
				i = 0;
				while(TRUE)
				{
					if(myMsg->payload[i] == '\n')
					{
						printf("%c", myMsg->payload[i]);
						i++;
						break;
					}
					else
					{
						printf("%c", myMsg->payload[i]);
						i++;
					}
				}
			}
			
			// Transport packet. If intended for this node, handle it.
			else if(myMsg->protocol == PROTOCOL_TCP && myMsg->dest == TOS_NODE_ID)
			{
				// Temp Socket Structs.
				socketStruct tempSocket;
				socketStruct* receivedSocket;
				
				// Iterator.
				int i;
				
				// SYN_ACK packet.
				pack SYN_ACK;
				
				receivedSocket = myMsg->payload;
				
				// Find the appropriate socket.
				for(i = 0; i < MAX_NUM_OF_SOCKETS; i++)
				{
					tempSocket = call Transport.getSocket(i);
					
					// Compare the port and source.
					// Make sure the Socket is listening.
					// Also check flag. Must be 1 for a SYN. If so, send a SYN_ACK.
					if (receivedSocket->socketState.flag == 1)
					{
						
						// Conditions hold true, reply with a SYN_ACK.
						// Update the state of the Socket.
						tempSocket.socketState.flag = 2;
						tempSocket.socketState.dest.port = receivedSocket->socketState.src;
						tempSocket.socketState.dest.addr = myMsg->src;
						tempSocket.socketState.state = SYN_RCVD;
						tempSocket.socketState.bufflen = receivedSocket->socketState.bufflen;
						call Transport.setSocket(tempSocket.fd, tempSocket);
						
						// Make the SYN_ACK.
						makePack(&SYN_ACK, TOS_NODE_ID, myMsg->src, myMsg->TTL, PROTOCOL_TCP, myMsg->seq, &tempSocket, (uint8_t) sizeof(tempSocket));
						
						dbg(TRANSPORT_CHANNEL, "SYN packet received from Node %d port %d, replying with SYN_ACK.\n", myMsg->src, receivedSocket->socketState.src);
						
						// Send out the SYN_ACK.
						call Sender.send(SYN_ACK, forwardPacketTo(&confirmedList, myMsg->src));
						return msg;
						
					} // End flag 1 handle.
					
					// If flag is 2, it is a SYN_ACK packet.
					else if(receivedSocket->socketState.flag == 2)
					{
						// Packet to reply to the SYN_ACK.
						// Specifies that a connection has been established.
						pack ACK;
						
						// Get the current state of the Socket.
						tempSocket = call Transport.getSocket(i);
						
						// Update the state of the Socket.
						tempSocket.socketState.flag = 7;
						tempSocket.socketState.dest.port = receivedSocket->socketState.src;
						tempSocket.socketState.dest.addr = myMsg->src;
						tempSocket.socketState.state = ESTABLISHED;
						tempSocket.socketState.bufflen = receivedSocket->socketState.bufflen;
						call Transport.setSocket(tempSocket.fd, tempSocket);
						
						// Make the ACK.
						makePack(&ACK, TOS_NODE_ID, myMsg->src, myMsg->TTL, PROTOCOL_TCP, myMsg->seq, &tempSocket, (uint8_t) sizeof(tempSocket));
					
						dbg(TRANSPORT_CHANNEL, "SYN_ACK has been received, a connection has been established, replying with an ACK.\n");
						
						// Send out the ACK.
						call Sender.send(ACK, forwardPacketTo(&confirmedList, myMsg->src));
						return msg;
						
					} // End flag 2 handle.
					
					// Give the all clear to send the DATA.
					else if(receivedSocket->socketState.flag == 7)
					{
						pack ACK;
						
						tempSocket = call Transport.getSocket(i);

						tempSocket.socketState.flag = 3;
						tempSocket.socketState.dest.port = receivedSocket->socketState.src;
						tempSocket.socketState.dest.addr = myMsg->src;
						tempSocket.socketState.state = ESTABLISHED;
						tempSocket.socketState.bufflen = receivedSocket->socketState.bufflen;
						call Transport.setSocket(tempSocket.fd, tempSocket);

						makePack(&ACK, TOS_NODE_ID, myMsg->src, myMsg->TTL, PROTOCOL_TCP, myMsg->seq, &tempSocket, (uint8_t) sizeof(tempSocket));
					
						call Sender.send(ACK, forwardPacketTo(&confirmedList, myMsg->src));
						return msg;
					}
					
					// If flag is 3, both sockets have established connection, and can send DATA.
					else if((receivedSocket->socketState.flag == 3) && (receivedSocket->socketState.dest.port == tempSocket.socketState.src))
					{
						// Temp Buffer to write onto.
						uint8_t buff[msgLength[msgsRcvd]];
						
						int i;
						
						// Get the current state of the Socket.
						tempSocket = call Transport.getSocket(i);
						
						dbg(TRANSPORT_CHANNEL, "ACK has been received, both sockets have completed three way handshake. Ready to send DATA.\n");
						dbg(TRANSPORT_CHANNEL, "Bufflen of the DATA packet is %d.\n", msgLength[msgsRcvd]);
						
						// Now create and send a DATA packet.
						for(i = 0; i < msgLength[msgsRcvd]; i++)
							buff[i] = i;
						
						call Transport.write(0, buff, buffLen, &confirmedList);
						
						// Update the state of the Socket.
						tempSocket.socketState.state = ESTABLISHED;
						call Transport.setSocket(tempSocket.fd, tempSocket);
						return msg;
						
					} // End flag 3 handle.
					
					//If flag is 4, it is a DATA packet.
					else if(receivedSocket->socketState.flag == 4)
					{
						// Data has been received, now to read it.
						
						// Make a DATA_ACK packet to let the other node know the data has been received.
						pack DATA_ACK;
						
						// The length of the buffer is the same as the value of the lastWritten index in the buffer.
						uint16_t bufflen;
						
						// Read the buffer from the DATA packet.
						call Transport.read(receivedSocket->fd, receivedSocket->socketState.sendBuff, 56);
						
						// Now send out an DATA_ACK, as the data has been received.
						// Get the current state of the Socket.
						tempSocket = call Transport.getSocket(i);
						
						// Update the state of the Socket.
						tempSocket.socketState.flag = 5;
						tempSocket.socketState.nextExpected = bufflen + 1;
						call Transport.setSocket(tempSocket.fd, tempSocket);
						
						// Make the DATA_ACK.
						makePack(&DATA_ACK, TOS_NODE_ID, myMsg->src, myMsg->TTL, PROTOCOL_TCP, myMsg->seq, &tempSocket, (uint8_t) sizeof(tempSocket));
					
						dbg(TRANSPORT_CHANNEL, "DATA has been received, sending out DATA_ACK.\n");
						
						// Send out the DATA_ACK.
						call Sender.send(DATA_ACK, forwardPacketTo(&confirmedList, myMsg->src));
						return msg;
						
					} // End flag 4 handle.
					
					//If flag is 5, it is a DATA_ACK packet.
					else if(receivedSocket->socketState.flag == 5)
					{
						dbg(TRANSPORT_CHANNEL, "DATA_ACK received, DATA successfully reached destination.\n");
						
						ackRcvd[msgsRcvd] = TRUE;
						msgsRcvd++;
						
						if(numMsgs > 1 && msgsRcvd < numMsgs)
						{
							dbg(TRANSPORT_CHANNEL, "Previous fragmented message received, sending next one...\n");
							signal CommandHandler.setTestClient(SRCPM, DPM, destinationM, msgLength[msgsRcvd]);
						}
						
						
						return msg;
						
					} // End flag 5 handle.
					else if(receivedSocket->socketState.flag == 8)
					{ 
						// SYN from chat client 
						// Update the state of the Socket.
						tempSocket.socketState.flag = 9;
						tempSocket.socketState.dest.port = receivedSocket->socketState.src;
						tempSocket.socketState.dest.addr = myMsg->src;
						tempSocket.socketState.state = SYN_RCVD;
						tempSocket.socketState.bufflen = receivedSocket->socketState.bufflen;
						call Transport.setSocket(tempSocket.fd, tempSocket);
						
						// Make the SYN_ACK.
						makePack(&SYN_ACK, TOS_NODE_ID, myMsg->src, myMsg->TTL, PROTOCOL_TCP, myMsg->seq, &tempSocket, (uint8_t) sizeof(tempSocket));
						
						dbg(TRANSPORT_CHANNEL, "The Chat Server has received a SYN packet from Chat Client Node %d port %d, replying with SYN_ACK.\n", myMsg->src, receivedSocket->socketState.src);
						
						// Send out the SYN_ACK.
						call Sender.send(SYN_ACK, forwardPacketTo(&confirmedList, myMsg->src));
						return msg;
						
					}
					else if(receivedSocket->socketState.flag == 9)
					{
						// Packet to reply to the SYN_ACK.
						// Specifies that a connection has been established.
						pack DATA;
						
						int j = 0;
						 
						
						DATA.src = TOS_NODE_ID;
						DATA.dest = myMsg->src;
						DATA.seq = 1;
						DATA.TTL = MAX_TTL;
						DATA.protocol = PROTOCOL_TCP_USER;
						
						memcpy(DATA.payload, &username, (uint8_t) sizeof(username));
					
						dbg(TRANSPORT_CHANNEL, "SYN_ACK has been received, a connection has been established. Sending username.\n");
						
						// Send out the Username.
						call Sender.send(DATA, forwardPacketTo(&confirmedList, myMsg->src));
						return msg;
					}
					
				} // End i loop.
				
			} // End else if(myMsg->protocol == PROTOCOL_TCP && myMsg->dest == TOS_NODE_ID).

			// Flooding or Forwarding. Also catches Transport packets not intended for this node.
			else if (myMsg->protocol == PROTOCOL_PING || myMsg->protocol == PROTOCOL_TCP)
			{
				int forwardTo;

				// Messaged received succesfully, reply with an ACK.
				if (myMsg->dest == TOS_NODE_ID)
				{
					makePack(&sendPackage, myMsg->src, myMsg->dest, MAX_TTL,PROTOCOL_PING,myMsg->seq,myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);

					// Message already received, drop it.
					if(checkPacket(sendPackage)){}

					else // Else 1.
					{
						dbg(FLOODING_CHANNEL, "Packet has Arrived to destination! Sending ACK.");
						dijkstra();
						forwardTo = forwardPacketTo(&confirmedList,myMsg->src);
						makePack(&sendPackage, TOS_NODE_ID, myMsg->src, 20,PROTOCOL_PINGREPLY,myMsg->seq,myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
						call Sender.send(sendPackage, forwardTo);

					} // End Else 1.
				} // End if (myMsg->dest == TOS_NODE_ID)

				// Message isn't meant for this node, therefore forward it.
				else // Else 2.
				{   
					int forwardTo;
					makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1, PROTOCOL_PING, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);

					if(checkPacket(sendPackage)){}

					else // Else 3.
					{
						dijkstra();
						forwardTo = forwardPacketTo(&confirmedList,myMsg->dest);

						if(forwardTo == 0) 
							printCostList(&lspMAP, TOS_NODE_ID);

						if(forwardTo == -1)
						{
							dbg(ROUTING_CHANNEL, "rechecking \n");
							dijkstra();
							forwardTo = forwardPacketTo(&confirmedList,myMsg->dest);

							if(forwardTo == -1){}

							else // Else 4.
							{
								dbg(ROUTING_CHANNEL,"Forwarding to %d and src is %d \n", forwardTo, TOS_NODE_ID);
								call Sender.send(sendPackage, forwardTo);

							} // End Else 4.
						} // End if(forwardTo == -1)

						else // Else 5.
						{
							dbg(ROUTING_CHANNEL,"Forwarding to %d and src is %d \n", forwardTo, TOS_NODE_ID);
							call Sender.send(sendPackage, forwardTo); 

						} // End Else 5.
					}// End Else 3.
				} // End Else 2.
			} // End else if (myMsg->protocol == PROTOCOL_PING)

			// Neighbor Discovery or Link State.
			else if (myMsg->dest == AM_BROADCAST_ADDR) 
			{
				if(myMsg->protocol == PROTOCOL_LINKSTATE)
				{
					int j, l;

					// If this packet hasn't been seen yet.
					if(!checkSeenLspPacks(sendPackage))
					{ 
						initializeMap(&lspMAP, myMsg->src);

						if(myMsg->src == TOS_NODE_ID){}

						else // Else 6.
						{
							for(j = 0; j <20; j++)
							{
								lspMAP[myMsg->src].cost[j] = myMsg->payload[j];
								if(lspMAP[myMsg->src].cost[j] != 255 || lspMAP[myMsg->src].cost[j] != 0 ){}
							} // End j loop.

							for(l = 1; l < 20; l++)
							{
								for(j = 1; j <20; j++)
								{ 
									if(lspMAP[l].cost[j] != 255 && lspMAP[l].cost[j] != 0)
										dbg(ROUTING_CHANNEL, "%d Neighbor %d, cost: %d\n",  l,j,lspMAP[l].cost[j] );

								} // End j loop.
							 } // End l loop.

							makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1, myMsg->protocol,myMsg->seq, (uint8_t*) myMsg->payload, 20);
							call Sender.send(sendPackage,AM_BROADCAST_ADDR);
						} // End Else 6.     
					} // End if(!checkSeenLspPacks(sendPackage)).		
				} //End if(myMsg->protocol == PROTOCOL_LINKSTATE).

				else if(myMsg->protocol == PROTOCOL_PINGREPLY)
				{
					neighbor Neighbor;
					neighbor neighbor_ptr;

					int k = 0;
					bool FOUND;
					FOUND = FALSE;
					size = call NeighborList.size();

					for(k = 0; k < call NeighborList.size(); k++) 
					{
						neighbor_ptr = call NeighborList.get(k);
						neighbor_ptr.Life++;
						if(neighbor_ptr.Node == myMsg->src)
						{
							FOUND = TRUE;
							neighbor_ptr.Life = 0;
						}
					} // End k loop.

					if(FOUND)
					{
						dbg(NEIGHBOR_CHANNEL,"Neighbor %d found in list\n", myMsg->src);
						netChange = FALSE;
					}
					else // Else 7.
					{
						Neighbor.Node = myMsg->src;
						Neighbor.Life = 0;
						call NeighborList.pushfront(Neighbor); //at index 0
						netChange = TRUE; //network change!
					} // End Else 7.

					for(k = 0; k < call NeighborList.size(); k++) 
					{
						neighbor_ptr = call NeighborList.get(k);

						if(neighbor_ptr.Life > 5) 
						{
							call NeighborList.remove(k);
							dbg(NEIGHBOR_CHANNEL, "Node %d life has expired dropping from NODE %d list\n", neighbor_ptr.Node, TOS_NODE_ID);
							dbg(ROUTING_CHANNEL, "CHANGE IN TOPOLOGY\n");
							netChange = TRUE;
						}
					} // End k loop.
				} // End else if(myMsg->protocol == PROTOCOL_PINGREPLY).

				else
					dbg(ROUTING_CHANNEL, "ERROR\n");   


			} // End else if (myMsg->dest == AM_BROADCAST_ADDR).

			else if(myMsg->protocol == PROTOCOL_PINGREPLY)
			{
				int forwardTo;

				if(myMsg->dest == TOS_NODE_ID)
				{ //ACK reached source
					makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1, PROTOCOL_PINGREPLY, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
					if(!checkPacket(sendPackage))
						dbg(FLOODING_CHANNEL,"Node %d recieved ACK from %d\n", TOS_NODE_ID,myMsg->src);        
				}
				else // Else 8.
				{
					dbg(FLOODING_CHANNEL, "Sending Ping Reply to %d! \n\n", myMsg->src);
					dijkstra();
					forwardTo = forwardPacketTo(&confirmedList,myMsg->src);
					dbg(ROUTING_CHANNEL,"Forwarding to %d and src is %d \n", forwardTo, TOS_NODE_ID);
					makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL - 1,PROTOCOL_PINGREPLY,myMsg->seq,myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
					call Sender.send(sendPackage, forwardTo);
				} // End Else 8.

			} // End else if(myMsg->protocol == PROTOCOL_PINGREPLY).

			return msg;

		} // End if(len==sizeof(pack)).

		dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
		return msg;

	} // End event.


	event void CommandHandler.ping(uint16_t destination, uint8_t *payload)
	{
		int forwardTo;
		
		dbg(GENERAL_CHANNEL, "PING EVENT \n");
		makePack(&sendPackage, TOS_NODE_ID, destination, 20, PROTOCOL_PING, seqNum, payload, PACKET_MAX_PAYLOAD_SIZE);
		
		dijkstra();
		forwardTo = forwardPacketTo(&confirmedList,destination);
		
		call Sender.send(sendPackage, forwardTo);
		seqNum++;
	}

	event void CommandHandler.printNeighbors()
	{
		printNeighborList();
	}

	event void CommandHandler.printRouteTable(){}

	event void CommandHandler.printLinkState(){}

	event void CommandHandler.printDistanceVector(){}

	event void CommandHandler.setTestServer(uint16_t port)
	{
		// Socket State variables.
		socket_addr_t address;
		socket_t fd;
		
		dbg(TRANSPORT_CHANNEL, "Testing server...\n");
		
		// Set the socket state.
		fd = call Transport.socket();
		address.addr = TOS_NODE_ID;
		address.port = port;
		
		
		
		if(call Transport.bind(fd, &address) == SUCCESS && call Transport.listen(fd) == SUCCESS)
			dbg(TRANSPORT_CHANNEL, "Socket %d is now listening.\n", fd);
		else
			dbg(TRANSPORT_CHANNEL, "Unable to edit socket %d.\n", fd);
	}
        
	event void CommandHandler.setTestClient(uint16_t SRCP, uint16_t DP, uint16_t destination, uint8_t bufflen)
	{
		// The SYN packet to be sent to the server.
		pack SYN;
		
		int i;
		double tempMath;
		
		// Socket state variables.
		socket_addr_t address; 
		socket_addr_t serverAdd;
		
		// Socket file descriptor.
		socket_t fd;
		
		dbg(TRANSPORT_CHANNEL, "Testing client...\n");
		
		// Get the socket fd.
		fd = call Transport.socket(); 
		
		// Source and source port.
		address.addr = TOS_NODE_ID;
		address.port = SRCP;
		
		// Destination and destination port.
		serverAdd.addr = destination;
		serverAdd.port = DP;
		
		buffLen = bufflen;
		SRCPM = SRCP;
		DPM = DP;
		destinationM = destination;
		
		if(buffLen > 128)
		{
			dbg(TRANSPORT_CHANNEL, "Message size larger than max buffer, fragmenting...\n");
			tempMath = buffLen / 128.0;
			numMsgs = ceil(tempMath);
			
			dbg(TRANSPORT_CHANNEL, "Number of messages that will be sent is: %d\n", numMsgs);
			
			msgLength[0] = 128;
			bufflen -= 128;
			ackRcvd[0] = FALSE;
			dbg(TRANSPORT_CHANNEL, "Message %d has length: %d\n", 0, msgLength[0]);
			
			for(i = 1; i < numMsgs - 1; i++)
			{
				msgLength[i] = bufflen;
				bufflen -= 128;
				ackRcvd[i] = FALSE;
				dbg(TRANSPORT_CHANNEL, "Message %d has length: %d\n", i, msgLength[i]);
			}
			msgLength[numMsgs - 1] = bufflen;
			dbg(TRANSPORT_CHANNEL, "Message %d has length: %d\n", numMsgs - 1, msgLength[numMsgs - 1]);
		}

		if (call Transport.bind(fd, &address) == SUCCESS)
		{
			if(buffLen > 128)
				call sendTimer.startPeriodic(1000);
		
			dbg(TRANSPORT_CHANNEL, "Attempting connection to port %d of node %d.\n", DP, destination);
			call Transport.connect(0, &serverAdd, &confirmedList, msgLength[msgsRcvd]);
		}
	}
	
    	event void CommandHandler.ClientClose(uint16_t dest, uint16_t destPort) 
	{
   		 pack FIN;
   		 socketStruct temp, temp2;
   		 int i;
   		// FIN.protocol = PROTOCOL_TCP;
   		 temp = call Transport.getSocket(temp.fd);
    		 temp.socketState.state = CLOSED;
    		 temp.socketState.flag = 6;
    		 temp.socketState.dest.port = dest;
   		 temp.socketState.dest.addr = destPort;
    		 makePack(&FIN, TOS_NODE_ID, dest, MAX_TTL, PROTOCOL_TCP, seqNum, &temp, (uint8_t) sizeof(temp));
    		 call Sender.send(FIN, forwardPacketTo(&confirmedList, dest));
		 dbg(TRANSPORT_CHANNEL, "Closed.\n");
	}

	event void CommandHandler.setAppServer()
	{
		// Socket State variables.
		socket_addr_t address;
		socket_t fd;
		
		// Set the socket state.
		fd = call Transport.socket();
		address.addr = TOS_NODE_ID;
		address.port = 41;
		
		dbg(TRANSPORT_CHANNEL, "Node %d port % d has been set as a chat server.\n", TOS_NODE_ID, address.port);
		
		if(call Transport.bind(fd, &address) == SUCCESS && call Transport.listen(fd) == SUCCESS)
			dbg(TRANSPORT_CHANNEL, "Socket %d is now listening.\n", fd);
		else
			dbg(TRANSPORT_CHANNEL, "Unable to edit socket %d.\n", fd);
	}

	event void CommandHandler.setAppClient(char* usrnm)
	{
		// Temp socket variables.
		socketStruct tempSocket;
		socket_addr_t address;
		
		// Iterator.
		int i = 0;
		int j = 0;
		
		// Allocate a socket.
		tempSocket.fd = call Transport.socket();
		tempSocket.socketState.dest.port = 41;
		tempSocket.socketState.dest.addr = 1;
		
		address.port = 80;
		address.addr = TOS_NODE_ID;
		
		dbg(TRANSPORT_CHANNEL, "Setting up chat client.\n");
		
		while(TRUE)
		{
			if(usrnm[i] == '\n')
			{
				username[i] = usrnm[i];
				i++;
				break;
			}
			else
			{
				username[i] = usrnm[i];
				i++;
			}
		}
		
		if (call Transport.bind(tempSocket.fd, &address) == SUCCESS)
		{
			call Transport.connectChatClient(tempSocket.fd, &tempSocket.socketState.dest, &confirmedList);
		}
	}
	
	event void CommandHandler.message(char* mssg)
	{
	
		pack message;
		
		char chat[25];
		
		// Iterator.
		int i;
		
		uint16_t dest = 1;
		
		i = 0;
		while(TRUE)
		{
			if(mssg[i] == '\n')
			{
				chat[i] = mssg[i];
				i++;
				break;
			}
			else
			{
				chat[i] = mssg[i];
				i++;
			}
		}
						
		message.src = TOS_NODE_ID;
		message.dest = 1;
		message.seq = 1;
		message.TTL = MAX_TTL;
		message.protocol = PROTOCOL_TCP_MSG;

		memcpy(message.payload, &chat, (uint8_t) sizeof(chat));
		
		dbg(TRANSPORT_CHANNEL, "Sending message.\n");
		
		call Sender.send(message, forwardPacketTo(&confirmedList, 1));
	}
	
	event void CommandHandler.whisper(char* destination, char* msg)
	{
		
	}

	void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
		Package->src = src;
		Package->dest = dest;
		Package->TTL = TTL;
		Package->seq = seq;
		Package->protocol = protocol;
		memcpy(Package->payload, payload, length);
	}

	bool checkPacket(pack Packet)
	{
		pack PacketMatch;
		if(call SeenPackList.isEmpty())
		{
			call SeenPackList.pushfront(Packet);
			return FALSE;
		}
		else
		{
			int i;
			int size = call SeenPackList.size();
			for(i = 0; i < size; i++)
			{
				PacketMatch = call SeenPackList.get(i);
				if( (PacketMatch.src == Packet.src) && (PacketMatch.dest == Packet.dest) && (PacketMatch.seq == Packet.seq) && (PacketMatch.protocol== Packet.protocol))
						return TRUE;
			}

		}
		call SeenPackList.pushfront(Packet);
		return FALSE;
	}

	void neighborDiscovery()
	{
		char* dummyMsg = "Hello\n";

		makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, MAX_TTL, PROTOCOL_PINGREPLY, -1, dummyMsg, PACKET_MAX_PAYLOAD_SIZE);
		call Sender.send(sendPackage, AM_BROADCAST_ADDR);

		if (printNodeNeighbors)
		{
			printNodeNeighbors = FALSE;
			printNeighborList();
		}
		else
			printNodeNeighbors = TRUE;
	}

	void printNeighborList()
	{
		int i;
		neighbor neighPtr;
		if(call NeighborList.size() == 0 )
			dbg(NEIGHBOR_CHANNEL,"No neighbors for node %d\n", TOS_NODE_ID);
			
		else
		{
			dbg(NEIGHBOR_CHANNEL,"Neighbors for node %d\n",TOS_NODE_ID);
			for(i = 0; i < call NeighborList.size(); i++)
			{
				neighPtr = call NeighborList.get(i);
				dbg(NEIGHBOR_CHANNEL,"NeighborNode: %d\n", neighPtr.Node);
			}
		}

	}


	void lspNeighborDiscoveryPacket()
	{
		int i;
		uint8_t lspCostList[20] = {-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1};
		initializeMap(&lspMAP, TOS_NODE_ID);
		for(i  =0; i < call NeighborList.size(); i++)
		{
			neighbor Neighbor = call NeighborList.get(i);
			lspCostList[Neighbor.Node] = 1;
			lspMAP[TOS_NODE_ID].cost[Neighbor.Node] = 1;
		}
		
	   	if(!call NeighborList.isEmpty())
		{
			lspSeqNum++;
		   	dbg(ROUTING_CHANNEL, "Sending LSP: SeqNum: %d\n", lspSeqNum);
			makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR,20, PROTOCOL_LINKSTATE, lspSeqNum, (uint8_t *) lspCostList, 20);
			call Sender.send(sendPackage,AM_BROADCAST_ADDR);
	   	}
	}


	bool checkSeenLspPacks(pack Packet)
	{
		pack PacketMatch;
		if(call SeenLspPackList.isEmpty())
		{
			call SeenLspPackList.pushfront(Packet);
			return FALSE;
		}
		else
		{
			int i;
			int size = call SeenLspPackList.size();
			for(i = 0; i < size; i++)
			{
				PacketMatch = call SeenLspPackList.get(i);//check for lsp from a certain node
				if( (PacketMatch.src == Packet.src) && (PacketMatch.protocol == Packet.protocol))
				{ 
					if(PacketMatch.seq == Packet.seq) 
						return TRUE;
					if(PacketMatch.seq < Packet.seq)
					{   
						call SeenLspPackList.remove(i);
						call SeenLspPackList.pushback(Packet);
						return FALSE;
					}
					return TRUE; //packet is found in list and has already been seen by node.
				}
			}
		}
		call SeenLspPackList.pushfront(Packet);
		return FALSE;
	}

	void dijkstra()
	{
		int i;	
		lspEntry lspTup, temp;
		
		initializeTable(&tentativeList); 
		initializeTable(&confirmedList);

		tablePushback(&tentativeList, temp = (lspEntry){TOS_NODE_ID,0,TOS_NODE_ID});
		
		while(!tableIsEmpty(&tentativeList))
		{
			if(!tableContains(&confirmedList, lspTup = getMinCost(&tentativeList))) //gets the minCost node from the tentative and removes it, then checks if it's in the confirmed list.
				if(tablePushback(&confirmedList,lspTup))
					dbg(ROUTING_CHANNEL,"PushBack from confirmedList dest:%d cost:%d nextHop:%d \n", lspTup.dest,lspTup.cost, lspTup.nextHop);
			
			for(i = 1; i < 20; i++)
			{
				temp = (lspEntry){i,lspMAP[lspTup.dest].cost[i]+lspTup.cost,(lspTup.nextHop == TOS_NODE_ID)?i:lspTup.nextHop};
				if(!tableContains(&confirmedList, temp) && lspMAP[lspTup.dest].cost[i] != 255 && lspMAP[i].cost[lspTup.dest] != 255 && replaceEntry(&tentativeList,temp,temp.cost))
						dbg(ROUTING_CHANNEL,"Replace from tentativeList dest:%d cost:%d nextHop:%d\n", temp.dest, temp.cost, temp.nextHop);
				else if(!tableContains(&confirmedList, temp) && lspMAP[lspTup.dest].cost[i] != 255 && lspMAP[i].cost[lspTup.dest] != 255 && tablePushback(&tentativeList, temp))
						dbg(ROUTING_CHANNEL,"PushBack from tentativeList dest:%d cost:%d nextHop:%d \n", temp.dest, temp.cost, temp.nextHop);
			}
		}
		
		dbg(ROUTING_CHANNEL, "Printing the ROUTING_CHANNEL table! \n");
		for(i = 0; i < confirmedList.entries; i++)
			dbg(ROUTING_CHANNEL, "dest:%d cost:%d nextHop:%d \n",confirmedList.lspEntries[i].dest,confirmedList.lspEntries[i].cost,confirmedList.lspEntries[i].nextHop);
	}

	int forwardPacketTo(lspTable* list, int dest)
	{	
		if(TOS_NODE_ID == 2)
			return 1;
			
		return getNextHop(list,dest);
	}


	/**
	 * let S_1 = Y_1
	 * Exponential Moving Average
	 * S_t = alpha*Y_t + (1-alpha)*S_(t-1)
	 */	
	float EMA(float prevEMA, float now,float weight)
	{
		float alpha = 0.5*weight;
		float averageEMA = alpha*now + (1-alpha)*prevEMA;
		return averageEMA;
	}


	void printlspMap(lspMap *list){
		int i,j;
		for(i = 0; i < 20; i++){
			for(j = 0; j < 20; j++){
				if(list[i].cost[j] != 0 && list[i].cost[j] != 255)
					dbg(ROUTING_CHANNEL, "src: %d  neighbor: %d cost: %d \n", i, j, list[i].cost[j]);
			}	
		}
		dbg(ROUTING_CHANNEL, "END \n\n");
	}

	void printCostList(lspMap *list, uint8_t nodeID) {
		uint8_t i;
		for(i = 0; i < 20; i++) {
			dbg(ROUTING_CHANNEL, "From %d To %d Costs %d", nodeID, i, list[nodeID].cost[i]);
		}
	}

	void initializeMap(lspMap *Map, int TOS_NODE_ID)
	{
		// Iterator.
		int i;
		
		// Go through the map and set each cost to a sentinel value.
		for(i = 0; i < maxEntries; i++)
			Map[TOS_NODE_ID].cost[i] = -1;
	}
	
	// Gets the entry with the lowest cost from the table, removes it, and then returns it.
	lspEntry getMinCost(lspTable* Table)
	{
		// Iterator.
		int i;

		// Index of the min cost node.
		int minNode;

		// Temporary lspEntry.
		lspEntry tempEntry;

		// Set the temporary entry's cost to a sentinel value.
		tempEntry.cost = 255;

		// Find the node with the min cost.
		for(i = 0; i < Table->entries; i++)
		{
			// If the current node it is on is less than the cost of the temp, then a new min cost node has been found.
			if(tempEntry.cost > Table->lspEntries[i].cost)
			{
				// Set temp as the new min cost node.
				tempEntry = Table->lspEntries[i];

				// Set the index of the min cost node.
				minNode = i;
			}
		}

		// Now remove the min cost node and return it.
		// As long as there are more than one entries in the table, it can do it this way.
		if(Table->entries > 1)
		{
			// Reset the tempEntry as the min cost node.
			tempEntry = Table->lspEntries[minNode];

			// "Swap" the min cost node with the last entry.
			Table->lspEntries[minNode] = Table->lspEntries[Table->entries - 1];

			// Decrement the entries "pointer".
			Table->entries--;

			// Return the min cost node.
			return tempEntry;
		}

		// Otherwise, the last entry must be the min cost node. Set the table as empty.
		else
		{
			// "Decrement" the entries "pointer".
			Table->entries = 0;

			// Return the min cost node.
			return Table->lspEntries[0];
		}
	}

}
