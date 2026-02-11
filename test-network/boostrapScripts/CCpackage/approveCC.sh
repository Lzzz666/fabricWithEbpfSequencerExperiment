export FABRIC_CFG_PATH=${PWD}/../../configs/configPeer
export CORE_PEER_TLS_ENABLED=true

export PEER0_ORG1_CA=${PWD}/../../organizations/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem
export CORE_PEER_LOCALMSPID=Org1MSP
export CORE_PEER_TLS_ROOTCERT_FILE=$PEER0_ORG1_CA
export CORE_PEER_MSPCONFIGPATH=${PWD}/../../organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_ADDRESS=localhost:12051

export CC_PACKAGE_ID=basic_1.0:c6a45e2d5563c883869149c3dbd941c22fbe27daa21f0552834f5a53fbb8058a
export CHANNEL_NAME=mychannel
export ORDERER_CA=${PWD}/../../organizations/ordererOrganizations/example.com/tlsca/tlsca.example.com-cert.pem

export ORDERER_ADDRESS=10.140.0.20:8050

peer lifecycle chaincode approveformyorg -o $ORDERER_ADDRESS --ordererTLSHostnameOverride orderer1.example.com --channelID $CHANNEL_NAME --name mychaincode --version 1.0 --package-id $CC_PACKAGE_ID --sequence 1 --tls --cafile $ORDERER_CA
