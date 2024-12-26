% -----------------------------------------------------------------------------
% Module: utils
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2013-01-15
% Description: This module contains utility functions.
% -----------------------------------------------------------------------------

- module(utils).
- export([k_hash/2, get_subtree_index/2, xor_distance/2, sort_node_list/2, empty_branches/2, print/1, print/2]).
- export([to_bit_list/1, print_routing_table/2, debugPrint/1, debugPrint/2, verbose/0]).


% This function is used to convert a bitstring into a list of bits.
%%% Used for debugging purposes. %%%
to_bit_list(<<>>) -> 
    [];
to_bit_list(<<Bit:1/bits, Rest/bits>>) ->
    if Bit == <<1:1>> -> 
        NewBit = 1;
    true -> 
        NewBit = 0
    end,
    [NewBit] ++ to_bit_list(Rest).


% This function is used to create a K-bit hash from a given data.
k_hash(Data, K) when is_integer(K), K > 0 -> 
    Hash = crypto:hash(sha256, Data),
    % Takes the first K bits of the hash
    <<KBits:K/bits, _/bits>> = Hash,
    KBits.


% This function is used to get the index of the subtree that contains the target id.
get_subtree_index(Binary1, Binary2) ->
    Xor = xor_distance(Binary1, Binary2),
    most_significant_bit_index(Xor).

% This function is used to get the index of the most significant bit in a binary.
most_significant_bit_index(Binary) ->
    most_significant_bit_index(Binary, 1).
% When the first bit is 1 or the binary is empty, the index is returned.
most_significant_bit_index(<<1:1, _/bits>>, Index) ->
    Index;
most_significant_bit_index(<<>>, Index) ->
    Index;
% Otherwise, the function is called recursively increasing the Index and removing the first bit.
most_significant_bit_index(<<_:1, Rest/bits>>, Index) ->
    most_significant_bit_index(Rest, Index + 1).


% This function is used to calculate the xor distance between two binary ids.
xor_distance(HashID1, HashID2) ->
    K = bit_size(HashID1),
    <<N1:K>> = HashID1,
    <<N2:K>> = HashID2,
    R = N1 bxor N2,
    <<R:K>>.

% This function is used to sort a list of nodes by their xor distance from a target id.
sort_node_list(NodeList, TargetId) ->
    lists:sort(
        fun({Key1, _}, {Key2, _}) -> 
            utils:xor_distance(TargetId, Key1) < utils:xor_distance(TargetId, Key2) 
        end, 
        NodeList
    ).

% 
empty_branches(RoutingTable, K) ->
    Tab2List = ets:tab2list(RoutingTable),
    length(Tab2List) < K.

% Debugging function to print the routing table of the node.
print_routing_table(RoutingTable, MyHash) ->
    ets:tab2list(RoutingTable),
    lists:foldl(
        fun({BranchID, NodeList}, Acc) ->
            if BranchID < bit_size(MyHash) ->
                <<FirstBits:BranchID/bits, _/bits>> = MyHash;
            true ->
                FirstBits = MyHash
            end,
            Acc ++ [{utils:to_bit_list(FirstBits), NodeList}]
        end,
        [],
        ets:tab2list(RoutingTable)
    ).

% Used to print console messages
print(Format)->
    io:format(Format).
print(Format, Data)->
    io:format(Format, Data).

% Used to get verbosity status
verbose() ->
    Result = get(verbose),
    if Result /= undefined ->
        Result;
    true ->
        false
    end.
% Used to print debugging messages
% It only pints when verbosity is set to true
debugPrint(Format)->
    doItIfVerbose(fun() -> io:format(Format) end).
debugPrint(Format, Data)->
    doItIfVerbose(fun() -> io:format(Format, Data) end).
% This function implements the verbosity check
doItIfVerbose(Fun) ->
    Verbose = verbose(),
    
    if Verbose ->
        Fun();
    true -> ok
    end.