% -----------------------------------------------------------------------------
% Module: utils
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2013-01-15
% Description: This module contains utility functions.
% -----------------------------------------------------------------------------

- module(utils).

- export([k_hash/2, get_subtree_index/2, xor_distance/2, sort_node_list/2, map_to_list/1, to_bit_list/1]).


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
    % Take the first K bits of the hash
    <<KBits:K/bits, _/bits>> = Hash,
    KBits.


% This function is used to get the index of the subtree that contains the target id.
get_subtree_index(TargetId, MyId) -> 
    FirstBitIndex = first_different_bit_index(xor_distance(TargetId, MyId)),
    FirstBitIndex.
% This function is used to get the index of the first different bit between two binary ids.
first_different_bit_index(Binary) ->
    first_different_bit_index(Binary, 1).
first_different_bit_index(<<Bit:1, Rest/bits>>, Index) ->
    case Bit of
        1 -> 
            Index;
        0 -> 
            first_different_bit_index(Rest, Index + 1)
    end;
first_different_bit_index(<<>>, Index) ->
    Index. 


% This function is used to calculate the xor distance between two binary ids.
xor_distance(HashID1, HashID2) ->
    xor_distance(HashID1, HashID2, <<>>).
xor_distance(<<>>, <<>>, Acc) ->
    Acc;
xor_distance(<<Bit1:1, Rest1/bits>>, <<Bit2:1, Rest2/bits>>, Acc) ->
    XorBit = Bit1 bxor Bit2,
    xor_distance(Rest1, Rest2, <<Acc/bits, XorBit:1>>).

% This function is used to sort a list of nodes by their xor distance from a target id.
sort_node_list(NodeList, TargetId) ->
    lists:sort(
        fun({Key1, _}, {Key2, _}) -> 
            utils:xor_distance(TargetId, Key1) < utils:xor_distance(TargetId, Key2) 
        end, 
        NodeList
    ).

% This function is used to convert a map into a list of key-value pairs, expanding lists of values.
% Used to convert the routing table into a list of key-value pairs.
map_to_list(Map) ->
    Pairs = maps:to_list(Map),
    lists:flatmap(fun expand/1, Pairs).

expand({Key, ValueList}) ->
    [ {Key, Value} || Value <- ValueList ].