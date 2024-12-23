% -----------------------------------------------------------------------------
% Module: utils
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2013-01-15
% Description: This module contains utility functions.
% -----------------------------------------------------------------------------

- module(utils).
- export([k_hash/2, get_subtree_index/2, xor_distance/2, sort_node_list/2, to_bit_list/1]).


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


% debug() ->
%     Start = erlang:monotonic_time(),
%     lists:foreach(fun(_) -> get_subtree_index(<<257:256>>, <<1:256>>) end, lists:seq(1, 100000)),
%     End = erlang:monotonic_time(),
%     Duration = End - Start,
%     io:format("Execution time: ~p microseconds~n", [Duration]).

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