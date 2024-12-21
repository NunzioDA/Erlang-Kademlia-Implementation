% -----------------------------------------------------------------------------
% Module: utils
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2013-01-15
% Description: This module contains utility functions.
% -----------------------------------------------------------------------------

- module(utils).

- export([k_hash/2, get_subtree_index/2, xor_distance/2]).

% This function is used to convert a byte into a list of bits.
byte_to_bit_list(Byte) ->
    lists:reverse([if
                     Byte band (1 bsl I) /= 0 -> 1;
                     true -> 0
                  end || I <- lists:seq(0, 7)]).

% This function is used to convert a list of bytes into a list of bits.
to_bit_list(Bytes)->
    lists:flatten([byte_to_bit_list(Byte) || Byte <- Bytes]).

% This function is used to create a K-bit hash from a given data.
k_hash(Data, K) when is_integer(K), K > 0 -> 
    Hash = crypto:hash(sha256, Data),   
    Bit_list = to_bit_list(binary:bin_to_list(Hash)),
    List = lists:sublist(Bit_list, K),
    List.

% This function is used to get the index of the subtree that contains the target id.
get_subtree_index(TargetId, MyId) -> 
    get_subtree_index(TargetId, MyId, 0).

get_subtree_index([], [], Index) -> 
    Index;
get_subtree_index([H|T1], [H|T2], Index) -> 
    get_subtree_index(T1,T2,Index + 1);
get_subtree_index([H|_], [H2|_], Index) when H =/= H2 -> 
    Index.
    
% This function is used to calculate the xor distance between two ids.
xor_distance([], []) -> 0;
xor_distance([H1|T1], [H2|T2]) ->
    case H1 =:= H2 of
        true -> Distance = 0;
        false -> Distance = math:pow(2,length(T1))
    end,
    Distance + xor_distance(T1, T2).