package main

import (
	"crypto/x509"
	"fmt"
	"os"
	"time"

	"github.com/hyperledger/fabric-gateway/pkg/client"
	"github.com/hyperledger/fabric-gateway/pkg/identity"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
)

const (
	mspID       = "Org1MSP"
	cryptoPath  = "../../organizations/peerOrganizations/org1.example.com"
	certPath    = cryptoPath + "/users/User1@org1.example.com/msp/signcerts"
	keyPath     = cryptoPath + "/users/User1@org1.example.com/msp/keystore"
	tlsCertPath = cryptoPath + "/peers/peer0.org1.example.com/tls/ca.crt"
)

func contractForPeer(peerEndpoint string, gatewayPeer string) *client.Contract {
	clientConnection := newGrpcConnection(gatewayPeer, peerEndpoint)

	id := newIdentity()
	sign := newSign()

	gw, err := client.Connect(
		id,
		client.WithSign(sign),
		client.WithClientConnection(clientConnection),
		client.WithEvaluateTimeout(5*time.Second),
		client.WithEndorseTimeout(15*time.Second),
		client.WithSubmitTimeout(5*time.Second),
		client.WithCommitStatusTimeout(1*time.Minute),
	)
	if err != nil {
		panic(err)
	}

	chaincodeName := "mychaincode"
	if ccname := os.Getenv("CHAINCODE_NAME"); ccname != "" {
		chaincodeName = ccname
	}
	channelName := "mychannel"
	if cname := os.Getenv("CHANNEL_NAME"); cname != "" {
		channelName = cname
	}

	network := gw.GetNetwork(channelName)
	return network.GetContract(chaincodeName)
}

func newGrpcConnection(gatewayPeer string, peerEndpoint string) *grpc.ClientConn {
	certificatePEM, err := os.ReadFile(tlsCertPath)
	if err != nil {
		panic(fmt.Errorf("failed to read TLS certificate file: %w", err))
	}
	certificate, err := identity.CertificateFromPEM(certificatePEM)
	if err != nil {
		panic(err)
	}
	certPool := x509.NewCertPool()
	certPool.AddCert(certificate)
	transportCredentials := credentials.NewClientTLSFromCert(certPool, gatewayPeer)

	connection, err := grpc.Dial(peerEndpoint, grpc.WithTransportCredentials(transportCredentials))
	if err != nil {
		panic(fmt.Errorf("failed to create gRPC connection: %w", err))
	}
	return connection
}

func newIdentity() *identity.X509Identity {
	certificatePEM, err := readFirstFile(certPath)
	if err != nil {
		panic(fmt.Errorf("failed to read certificate file: %w", err))
	}
	certificate, err := identity.CertificateFromPEM(certificatePEM)
	if err != nil {
		panic(err)
	}
	id, err := identity.NewX509Identity(mspID, certificate)
	if err != nil {
		panic(err)
	}
	return id
}

func newSign() identity.Sign {
	privateKeyPEM, err := readFirstFile(keyPath)
	if err != nil {
		panic(fmt.Errorf("failed to read private key file: %w", err))
	}
	privateKey, err := identity.PrivateKeyFromPEM(privateKeyPEM)
	if err != nil {
		panic(err)
	}
	sign, err := identity.NewPrivateKeySign(privateKey)
	if err != nil {
		panic(err)
	}
	return sign
}
