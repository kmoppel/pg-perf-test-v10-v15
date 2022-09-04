#!/bin/bash

set -e

VMS_TO_CREATE=5
VM_BASENAME=dbre-pg-perf-testing-ins-
MACHINE_TYPE=e2-standard-4 # gcloud compute machine-types list --zones europe-west1-b
ZONE=europe-west1-b
DISK_SIZE=50GB
SSH_KEY=$(cat ~/.ssh/id_rsa.pub)

TEST_SCRIPTS_PATH=./

declare -a INS_NAMES

for i in $(seq 1 $VMS_TO_CREATE) ; do

    ins_name="${VM_BASENAME}${i}"
    INS_NAMES+=$ins_name
    echo "Creating VM $ins_name ..."

    gcloud compute instances create $ins_name --machine-type $MACHINE_TYPE --labels=team=dbre --zone $ZONE --boot-disk-size $DISK_SIZE --metadata=ssh-keys="$USER:$SSH_KEY"
    ip=$(gcloud compute instances describe $ins_name --zone $ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
    
    echo "Create OK. IP for $ins_name: $ip"
    echo "Sleeping for 30s for instance to boot ..."
    sleep 30

    echo "Copying PG setup script to test host ..."
    scp pg_instances_setup_ubuntu.sh ${ip}:
    
    echo "Setting up all Postgres versions ..."
    ssh ${ip} bash pg_instances_setup_ubuntu.sh >/dev/null

    echo "Copying test scripts to $ins_name ..."
    rsync -av $TEST_SCRIPTS_PATH/run_pgbench_testset.sh $TEST_SCRIPTS_PATH/*.sql $TEST_SCRIPTS_PATH/*.conf $ip:

    echo "Starting the test in tmux ..."
    echo "ssh ${ip} tmux new-session -d -s perftest bash run_pgbench_testset.sh"
    ssh ${ip} tmux new-session -d -s perftest bash run_pgbench_testset.sh

    echo "Test started for ${ip}"

done

echo "To delete all VMs after testing run:"
echo "  gcloud compute instances delete --quiet --zone $ZONE ${INS_NAMES[@]}"
echo -e "\nDone"
