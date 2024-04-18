#!/bin/bash
#set -euo pipefail

# Create a private pool for Cloud Build so that it can access the *PRIVATE* GKE cluster

# Based on Tutorial:
# https://cloud.google.com/build/docs/private-pools/accessing-private-gke-clusters-with-cloud-build-private-pools

PROJECT="test-clientmq"
REGION="europe-west1"
ZONE="europe-west1-b"
PRIVATE_CLUSTER_NAME="default-cluster"
PRIVATE_POOL_NAME="private-pool"
PRIVATE_POOL_PEERING_VPC_NAME="private-pool-vpn"
GKE_SUBNET_RANGE="10.244.252.0/22"
RESERVED_RANGE_NAME="private-pool-range"
PRIVATE_POOL_NETWORK="192.168.0.0"
PRIVATE_POOL_PREFIX="20"
GKE_PEERING_VPC_NAME='default-net'
NETWORK_1=$PRIVATE_POOL_PEERING_VPC_NAME
NETWORK_2=$GKE_PEERING_VPC_NAME
IP_STACK='IPV4_ONLY'
GW_NAME_1='private-poool-ha-gw-1'
GW_NAME_2='private-poool-ha-gw-2'
ROUTER_NAME_1='private-pool-router-1'
PEER_ASN_1='65001'
ROUTER_NAME_2='private-pool-router-2'
PEER_ASN_2='65002'
TUNNEL_NAME_GW1_IF0='private-pool-gw1-if0'
TUNNEL_NAME_GW1_IF1='private-pool-gw1-if1'
TUNNEL_NAME_GW2_IF0='private-pool-gw2-if0'
TUNNEL_NAME_GW2_IF1='private-pool-gw2-if1'
IKE_VERS='2'
SHARED_SECRET='cYLjnJlkN+L1Mc69f1AH1Jy5jHFDPfzk'
INT_NUM_0='0'
INT_NUM_1='1'
ROUTER_1_INTERFACE_NAME_0='private-pool-gw1-if0-interface'
ROUTER_1_INTERFACE_NAME_1='private-pool-gw1-if1-interface'
ROUTER_2_INTERFACE_NAME_0='private-pool-gw2-if0-interface'
ROUTER_2_INTERFACE_NAME_1='private-pool-gw2-if1-interface'
IP_ADDRESS_1='169.254.0.1'
IP_ADDRESS_2='169.254.1.1'
IP_ADDRESS_3='169.254.0.2'
IP_ADDRESS_4='169.254.1.2'
MASK_LENGTH='30'
PEER_NAME_GW1_IF0='private-pool-gw1-if0-peer'
PEER_NAME_GW1_IF1='private-pool-gw1-if1-peer'
PEER_NAME_GW2_IF0='private-pool-gw2-if0-peer'
PEER_NAME_GW2_IF1='private-pool-gw2-if1-peer'
PEER_IP_ADDRESS_1=$IP_ADDRESS_3
PEER_IP_ADDRESS_2=$IP_ADDRESS_4
PEER_IP_ADDRESS_3=$IP_ADDRESS_1
PEER_IP_ADDRESS_4=$IP_ADDRESS_2
# This CIDR is from 'master-ipv4-cidr' in file 'setup-faasd-worker-cluster'
CLUSTER_CONTROL_PLANE_CIDR='172.16.0.16/28'

function build {
    # FYI - the region here is actually the zone b/c thats how it was configured in 'setup-faasd-worker-cluster'
    GKE_PEERING_NAME=$(gcloud container clusters describe $PRIVATE_CLUSTER_NAME --project=$PROJECT --region=$ZONE --format='value(privateClusterConfig.peeringName)')
    gcloud compute networks peerings update $GKE_PEERING_NAME \
        --network=$GKE_PEERING_VPC_NAME \
        --export-custom-routes \
        --no-export-subnet-routes-with-public-ip

    # Create VPC Peering Network
    gcloud compute networks create $PRIVATE_POOL_PEERING_VPC_NAME \
        --subnet-mode=CUSTOM
    # Create a Cloud Build Private Pool
    gcloud compute addresses create $RESERVED_RANGE_NAME \
        --global \
        --purpose=VPC_PEERING \
        --addresses=$PRIVATE_POOL_NETWORK \
        --prefix-length=$PRIVATE_POOL_PREFIX \
        --network=$PRIVATE_POOL_PEERING_VPC_NAME
    gcloud services enable servicenetworking.googleapis.com
    gcloud services vpc-peerings connect \
        --service=servicenetworking.googleapis.com \
        --ranges=$RESERVED_RANGE_NAME \
        --network=$PRIVATE_POOL_PEERING_VPC_NAME
    gcloud compute networks peerings update servicenetworking-googleapis-com \
        --network=$PRIVATE_POOL_PEERING_VPC_NAME \
        --export-custom-routes \
        --no-export-subnet-routes-with-public-ip
    gcloud builds worker-pools create $PRIVATE_POOL_NAME \
        --region=$REGION \
        --peered-network="projects/$PROJECT/global/networks/$PRIVATE_POOL_PEERING_VPC_NAME"


    # Create two fully configured HA VPN gateways that connect to each other
    # Link: https://cloud.google.com/network-connectivity/docs/vpn/how-to/creating-ha-vpn2#creating-ha-gw-2-gw-and-tunnel
    gcloud compute vpn-gateways create $GW_NAME_1 \
    --network=$NETWORK_1 \
    --region=$REGION \
    --stack-type=$IP_STACK
    gcloud compute vpn-gateways create $GW_NAME_2 \
    --network=$NETWORK_2 \
    --region=$REGION \
    --stack-type=$IP_STACK

    # Create Router 1
    gcloud compute routers create $ROUTER_NAME_1 \
    --region=$REGION \
    --network=$NETWORK_1 \
    --asn=$PEER_ASN_1
    # Create Router 2
    gcloud compute routers create $ROUTER_NAME_2 \
    --region=$REGION \
    --network=$NETWORK_2 \
    --asn=$PEER_ASN_2

    # Create VPN Tunnel 1
    gcloud compute vpn-tunnels create $TUNNEL_NAME_GW1_IF0 \
        --peer-gcp-gateway=$GW_NAME_2 \
        --region=$REGION \
        --ike-version=$IKE_VERS \
        --shared-secret=$SHARED_SECRET \
        --router=$ROUTER_NAME_1 \
        --vpn-gateway=$GW_NAME_1 \
        --interface=$INT_NUM_0
    gcloud compute vpn-tunnels create $TUNNEL_NAME_GW1_IF1 \
        --peer-gcp-gateway=$GW_NAME_2 \
        --region=$REGION \
        --ike-version=$IKE_VERS \
        --shared-secret=$SHARED_SECRET \
        --router=$ROUTER_NAME_1 \
        --vpn-gateway=$GW_NAME_1 \
        --interface=$INT_NUM_1
    # Create VPN Tunnel 2
    gcloud compute vpn-tunnels create $TUNNEL_NAME_GW2_IF0 \
        --peer-gcp-gateway=$GW_NAME_1 \
        --region=$REGION \
        --ike-version=$IKE_VERS \
        --shared-secret=$SHARED_SECRET \
        --router=$ROUTER_NAME_2 \
        --vpn-gateway=$GW_NAME_2 \
        --interface=$INT_NUM_0
    gcloud compute vpn-tunnels create $TUNNEL_NAME_GW2_IF1 \
        --peer-gcp-gateway=$GW_NAME_1 \
        --region=$REGION \
        --ike-version=$IKE_VERS \
        --shared-secret=$SHARED_SECRET \
        --router=$ROUTER_NAME_2 \
        --vpn-gateway=$GW_NAME_2 \
        --interface=$INT_NUM_1

    # Create Router Interface 1
    gcloud compute routers add-interface $ROUTER_NAME_1 \
        --interface-name=$ROUTER_1_INTERFACE_NAME_0 \
        --ip-address=$IP_ADDRESS_1 \
        --mask-length=$MASK_LENGTH \
        --vpn-tunnel=$TUNNEL_NAME_GW1_IF0 \
        --region=$REGION
    gcloud compute routers add-bgp-peer $ROUTER_NAME_1 \
        --peer-name=$PEER_NAME_GW1_IF0 \
        --interface=$ROUTER_1_INTERFACE_NAME_0 \
        --peer-ip-address=$PEER_IP_ADDRESS_1 \
        --peer-asn=$PEER_ASN_2 \
        --region=$REGION
    gcloud compute routers add-interface $ROUTER_NAME_1 \
        --interface-name=$ROUTER_1_INTERFACE_NAME_1 \
        --ip-address=$IP_ADDRESS_2 \
        --mask-length=$MASK_LENGTH \
        --vpn-tunnel=$TUNNEL_NAME_GW1_IF1 \
        --region=$REGION
    gcloud compute routers add-bgp-peer $ROUTER_NAME_1 \
        --peer-name=$PEER_NAME_GW1_IF1 \
        --interface=$ROUTER_1_INTERFACE_NAME_1 \
        --peer-ip-address=$PEER_IP_ADDRESS_2 \
        --peer-asn=$PEER_ASN_2 \
        --region=$REGION
    # Create Router Interface 2
    gcloud compute routers add-interface $ROUTER_NAME_2 \
        --interface-name=$ROUTER_2_INTERFACE_NAME_0 \
        --ip-address=$IP_ADDRESS_3 \
        --mask-length=$MASK_LENGTH \
        --vpn-tunnel=$TUNNEL_NAME_GW2_IF0 \
        --region=$REGION
    gcloud compute routers add-bgp-peer $ROUTER_NAME_2 \
        --peer-name=$PEER_NAME_GW2_IF0 \
        --interface=$ROUTER_2_INTERFACE_NAME_0 \
        --peer-ip-address=$PEER_IP_ADDRESS_3 \
        --peer-asn=$PEER_ASN_1 \
        --region=$REGION
    gcloud compute routers add-interface $ROUTER_NAME_2 \
        --interface-name=$ROUTER_2_INTERFACE_NAME_1 \
        --ip-address=$IP_ADDRESS_4 \
        --mask-length=$MASK_LENGTH \
        --vpn-tunnel=$TUNNEL_NAME_GW2_IF1 \
        --region=$REGION
    gcloud compute routers add-bgp-peer $ROUTER_NAME_2 \
        --peer-name=$PEER_NAME_GW2_IF1 \
        --interface=$ROUTER_2_INTERFACE_NAME_1 \
        --peer-ip-address=$PEER_IP_ADDRESS_4 \
        --peer-asn=$PEER_ASN_1 \
        --region=$REGION

    # Update BGP Session to advertise routes
    gcloud compute routers update-bgp-peer $ROUTER_NAME_1 \
        --peer-name=$PEER_NAME_GW1_IF0 \
        --region=$REGION \
        --advertisement-mode=CUSTOM \
        --set-advertisement-ranges=$PRIVATE_POOL_NETWORK/$PRIVATE_POOL_PREFIX
    gcloud compute routers update-bgp-peer $ROUTER_NAME_1 \
        --peer-name=$PEER_NAME_GW1_IF1 \
        --region=$REGION \
        --advertisement-mode=CUSTOM \
        --set-advertisement-ranges=$PRIVATE_POOL_NETWORK/$PRIVATE_POOL_PREFIX
    gcloud compute routers update-bgp-peer $ROUTER_NAME_2 \
        --peer-name=$PEER_NAME_GW2_IF0 \
        --region=$REGION \
        --advertisement-mode=CUSTOM \
        --set-advertisement-ranges=$CLUSTER_CONTROL_PLANE_CIDR
    gcloud compute routers update-bgp-peer $ROUTER_NAME_2 \
        --peer-name=$PEER_NAME_GW2_IF1 \
        --region=$REGION \
        --advertisement-mode=CUSTOM \
        --set-advertisement-ranges=$CLUSTER_CONTROL_PLANE_CIDR

    # Enable cloud build access to the GKE Cluster Control Plane
    # FYI - the region here is actually the zone b/c thats how it was configured in 'setup-faasd-worker-cluster'
    gcloud container clusters update $PRIVATE_CLUSTER_NAME \
        --enable-master-authorized-networks \
        --region=$ZONE \
        --master-authorized-networks=$PRIVATE_POOL_NETWORK/$PRIVATE_POOL_PREFIX
    # Enable Cloud Build ServiceAccount access to the GKE Cluster Control Plane
    gcloud projects add-iam-policy-binding $PROJECT \
        --member=serviceAccount:$PROJECT_NUMBER@cloudbuild.gserviceaccount.com \
        --role=roles/container.developer \
        --condition=None
}

function destroy {
    # The below line deletes the faasd-worker cluster and should only be used if you want to delete the entire setup
    # gcloud container clusters delete $PRIVATE_CLUSTER_NAME \
    #     --region=$ZONE \
    #     --async
    gcloud builds worker-pools delete $PRIVATE_POOL_NAME \
        --region=$REGION
    gcloud services vpc-peerings delete \
        --network=$PRIVATE_POOL_PEERING_VPC_NAME \
        --async
    gcloud compute addresses delete $RESERVED_RANGE_NAME \
        --global
    gcloud compute vpn-tunnels delete \
        $TUNNEL_NAME_GW1_IF0 \
        $TUNNEL_NAME_GW1_IF1 \
        $TUNNEL_NAME_GW2_IF0 \
        $TUNNEL_NAME_GW2_IF1 \
        --region=$REGION
    gcloud compute routers delete \
        $ROUTER_NAME_1 \
        $ROUTER_NAME_2 \
        --region=$REGION
    gcloud compute vpn-gateways delete \
        $GW_NAME_1 \
        $GW_NAME_2 \
        --region=$REGION
    gcloud compute networks delete \
        $PRIVATE_POOL_PEERING_VPC_NAME
}


gcloud config set project $PROJECT
PROJECT_NUMBER=$(gcloud projects describe $PROJECT --format 'value(projectNumber)')
cmd="$1"
shift
if [ "$cmd" == 'build' ]; then
    build "$@"
elif [ "$cmd" == 'destroy' ]; then
    destroy "$@"
else
    echo "Invalid argument"
fi;
