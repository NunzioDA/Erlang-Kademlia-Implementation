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

## .gitignore

The `.gitignore` file is configured to ignore all `.beam` and `.dump` files.
