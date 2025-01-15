# Erlang Kademlia Implementation



- **Authors**: Nunzio D'Amore, Francesco Rossi
- **Description**: This project aims to emulate a Kademlia network in Erlang, where each process represents a node within the network.


## Getting Started
1. Move into execution directory:

    ```sh
    cd execution
    ```

2. Start the Erlang shell:

    ```sh
    erl
    ```    

3. Compile the modules using the module compiler:

    ```sh
    c(compiler).
    compiler:compile().
    ```

4. Use the starter module to start the simulation:

    ```erlang
    starter:start().
    ```

## Shell commands
Use the following commands to start a custom simulation and control the network.
### Starter commands
1. Use start_new_nodes/4 to start a network or to add new nodes to a previousely started network (In this case keep K consistent with the existing nodes):

    ```erlang
    starter:start_new_nodes(Bootstraps, Nodes, K, T).
    ```
2. If, on the other hand, you do not wish to add new nodes but rather initiate a new network destroy the previously started network before using start_new_nodes/4:

    ```erlang
    starter:destroy().
    ```
### Nodes information
1. Getting enrolled bootstrap nodes:

    ```erlang
    analytics_collector:get_bootstrap_list().
    ``` 
2. Getting enrolled nodes:

    ```erlang
    analytics_collector:get_node_list().
    ``` 

### Node commands
1. Getting a node routing table:

    ```erlang
    node:get_routing_table(NodePid).
    ``` 
2. Distributing a value in the network:

    ```erlang
    node:distribute(NodePid, Key, Value).
    ``` 
3. Looking up for a saved value in the network:

    ```erlang
    node:lookup(NodePid, Key).
    ``` 
4. Finding the nearest node to a specified value:

    ```erlang
    node:shell_find_nearest_nodes(NodePid, Value).
    ``` 
5. Pinging a node:

    ```erlang
    node:ping(NodePid).
    ``` 
6. Making a node ping another node:

    ```erlang
    node:send_ping(NodeFrom, NodeTo).
    ``` 
7. Killing a node:

    ```erlang
    node:kill(NodePid).
    ``` 
### Metrics commands
1. Getting nodes that finished join procedure:

    ```erlang
    analytics_collector:get_finished_join_nodes().
    ``` 
2. Getting join mean time:

    ```erlang
    analytics_collector:join_procedure_mean_time().
    ```
3. Getting nodes that started filling the routing table:

    ```erlang
    analytics_collector:get_started_filling_routing_table_nodes().
    ``` 
4. Getting nodes that finished filling the routing table:

    ```erlang
    analytics_collector:get_finished_filling_routing_table_nodes().
    ``` 
5. Getting fill routing table mean time:

    ```erlang
    analytics_collector:filling_routing_table_mean_time().
    ```
6. Getting nodes that started a distribution process:

    ```erlang
    analytics_collector:get_started_distribute().
    ``` 
7. Getting nodes that finished a distribution process:

    ```erlang
    analytics_collector:get_finished_distribute().
    ``` 
8. Getting distribute procedure mean time:

    ```erlang
    analytics_collector:distribute_mean_time().
    ```
9. Getting a list of nodes that stored a given key:

    ```erlang
    analytics_collector:get_nodes_that_stored().
    ```
### Flushing events
1. Flushing join events:

    ```erlang
    analytics_collector:flush_join_events().
    ``` 
2. Flushing filling routing table events:

    ```erlang
    analytics_collector:flush_filling_routing_table_events().
    ``` 
3. Flushing distribute events:

    ```erlang
    analytics_collector:flush_distribute_events().
    ``` 
4. Flushing nodes that stored a value:

    ```erlang
    analytics_collector:flush_nodes_that_stored().
    ```
## .gitignore

The `.gitignore` file is configured to ignore all `.beam` and `.dump` files.
