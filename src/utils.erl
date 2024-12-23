% -----------------------------------------------------------------------------
% Module: utils
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2013-01-15
% Description: This module contains utility functions.
% -----------------------------------------------------------------------------

- module(utils).
- export([k_hash/2, get_subtree_index/2, xor_distance/2, sort_node_list/2, 
    map_to_list/1, to_bit_list/1]).


% This function is used to convert a byte into a list of bits.
byte_to_bit_list(Byte) ->
    lists:reverse([if
                     Byte band (1 bsl I) /= 0 -> 1;
                     true -> 0
                  end || I <- lists:seq(0, 7)]).

% This function is used to convert a list of bytes into a list of bits.
to_bit_list(Bytes)->
    HaLi = binary:bin_to_list(Bytes),
    lists:flatten([byte_to_bit_list(Byte) || Byte <- HaLi]).


% This function is used to create a K-bit hash from a given data.
k_hash(Data, K) when is_integer(K), K > 0, K rem 8 == 0 -> 
    Hash = crypto:hash(sha256, Data),
    KBits = binary:part(Hash, {0, ceil(K / 8)}),
    KBits.

% This function is used to get the index of the subtree that contains the target id.
get_subtree_index(TargetId, MyId) -> 
    FirstBitIndex = first_different_bit_index(xor_distance(TargetId, MyId)),
    FirstBitIndex.
% This function is used to get the index of the first different bit between two binary ids.
first_different_bit_index(Binary) when is_binary(Binary) ->
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
xor_distance(HashId1, HashId2) when is_binary(HashId1), is_binary(HashId2) ->
    Result = lists:zipwith(fun(A, B) -> A bxor B end, binary:bin_to_list(HashId1), binary:bin_to_list(HashId2)),
    binary:list_to_bin(Result).

% This function is used to sort a list of nodes by their xor distance from a target id.
sort_node_list(NodeList, TargetId) ->
    lists:sort(
        fun({Key1, _}, {Key2, _}) -> 
            utils:xor_distance(TargetId, Key1) < utils:xor_distance(TargetId, Key2) 
        end, 
        NodeList
    ).

% This function is used to convert a map into a list of key-value pairs, expanding 
% lists of values. Used to convert the routing table into a list of key-value pairs.
map_to_list(Map) ->
    Pairs = maps:to_list(Map),
    lists:flatmap(fun expand/1, Pairs).

expand({Key, ValueList}) ->
    [ {Key, Value} || Value <- ValueList ].