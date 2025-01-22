% -----------------------------------------------------------------------------
% Module: utils
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2024-12-20
% Description: This module contains utility functions.
% -----------------------------------------------------------------------------

- module(utils).
- export([k_hash/2, get_subtree_index/2, xor_distance/2, sort_node_list/2, print_progress/2]).
- export([empty_branches/2, remove_duplicates/1, remove_contacted_nodes/2, print/1, print/2]).
- export([to_bit_list/1, print_routing_table/1, debug_print/1, debug_print/2, do_it_if_verbose/1]).
- export([verbose/0, set_verbose/1,most_significant_bit_index/1, most_significant_bit_index/2]).
- export([print_centered_rectangle/1, print_centered_rectangle/2, pid_in_routing_table/3, center/2]).

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
    [NewBit] ++ ?MODULE:to_bit_list(Rest)
.

% This function is used to create a K-bit hash from a given data.
k_hash(Data, K) when is_pid(Data) ->
    k_hash(pid_to_list(Data), K);
k_hash(Data, K) when is_integer(K), K > 0 -> 
    Hash = crypto:hash(sha256, Data),
    % Takes the first K bits of the hash
    <<KBits:K/bits, _/bits>> = Hash,
    KBits
.

% This function is used to get the index of the subtree that contains the target id.
get_subtree_index(Binary1, Binary2) ->
    Xor = ?MODULE:xor_distance(Binary1, Binary2),
    MostSignificant = ?MODULE:most_significant_bit_index(Xor),
    BitSize = bit_size(Binary1),
    if MostSignificant > BitSize ->
        BitSize;
    true ->
        MostSignificant
    end
.

% This function is used to get the index of the most significant bit in a binary.
most_significant_bit_index(Binary) ->
    ?MODULE:most_significant_bit_index(Binary, 1)
.
% When the first bit is 1 or the binary is empty, the index is returned.
most_significant_bit_index(<<1:1, _/bits>>, Index) ->
    Index;
most_significant_bit_index(<<>>, Index) ->
    Index;
% Otherwise, the function is called recursively increasing the Index and removing the first bit.
most_significant_bit_index(<<_:1, Rest/bits>>, Index) ->
    ?MODULE:most_significant_bit_index(Rest, Index + 1)
.


% This function is used to calculate the xor distance between two binary ids.
xor_distance(HashID1, HashID2) ->
    K = bit_size(HashID1),
    <<N1:K>> = HashID1,
    <<N2:K>> = HashID2,
    R = N1 bxor N2,
    <<R:K>>
.

% This function is used to sort a list of nodes by their XOR distance from a target ID.
% Using the PID along with the XOR distance to sort the node list makes the network more  
% reliable, even with a large number of collisions. This is particularly helpful when 
% the network has a large number of nodes and a small K parameter.
sort_node_list(NodeList, TargetId) ->
    lists:sort(
        fun({Key1, Pid1}, {Key2, Pid2}) -> 
            Distance1 = ?MODULE:xor_distance(TargetId, Key1),
            Distance2 = ?MODULE:xor_distance(TargetId, Key2),
            if Distance1 < Distance2 -> 
                true;
            true ->
                % If the distance is equal sort the 
                % list based on the Pid
                if Distance1 == Distance2 ->
                    Pid1 < Pid2;
                true ->
                    false
                end
            end
        end, 
        NodeList
    )
.

% This function is used to remove duplicates from a list
remove_duplicates(List) ->
    lists:foldl(
        fun(Element, Acc) ->
            Condition = lists:member(Element, Acc),
            case Condition of
                true -> Acc; 
                false -> Acc ++ [Element]
            end
        end, 
        [], 
        List
    )
.

% This function is used to filter already contacted nodes
% from a nodes list
remove_contacted_nodes(NodesList, ContactedNodes) ->
    lists:foldl(
        fun(Element, Acc) ->
            {_,Pid} = Element,
            Condition = lists:member(Pid, ContactedNodes),
            case Condition of
                true -> Acc; 
                false -> Acc ++ [Element]
            end
        end, 
        [],
        NodesList
    )
.

% This function is used to check if 
% there are empty branches in the routing table.
empty_branches(RoutingTable, K) ->

    AnyEmpty = lists:any(
        fun(Element) ->
            case ets:lookup(RoutingTable,Element) of
                [{_,[]}] -> true;
                [] -> true;
                _ ->
                    false
            end
        end,
        lists:seq(1,K)    
    ),

    AnyEmpty
.

% branches_with_less_than(RoutingTable, K, MinLen) ->

    % AnyEmpty = lists:any(
    %     fun(Element) ->
    %         case ets:lookup(RoutingTable,Element) of
    %             [{_,Nodes}] -> 
    %                 Length = length(Nodes),
    %                 if Length =< MinLen -> true;
    %                 true -> false
    %                 end;
    %             [] -> true;
    %             _ ->
    %                 false
    %         end
    %     end,
    %     lists:seq(1,K)    
    % ),

    % AnyEmpty.

% This function is used to check if 
% a pid is contained in a routing table
pid_in_routing_table(RoutingTable, Pid, K) ->
    BranchId = ?MODULE:get_subtree_index(?MODULE:k_hash(Pid, K), com:my_hash_id(K)),
    
    case ets:lookup(RoutingTable, BranchId) of
        [{_, NodeList}] ->
            lists:keymember(Pid, 2, NodeList);
        _ ->
            false
    end
.

% --------------------------------------------------------
% Print functions
% --------------------------------------------------------

% This function is used to center a string
% in a rectangle of a given width
center(String, Width) ->
    Padding = Width - length(String),
    LeftPadding = Padding div 2,
    RightPadding = Padding - LeftPadding,
    LeftSpaces = lists:duplicate(LeftPadding, $ ),
    RightSpaces = lists:duplicate(RightPadding, $ ),
    lists:concat([LeftSpaces, String, RightSpaces])
.

% This function is used to print 
% the title.
% Content is a list of strings
print_centered_rectangle(Content) ->
    LongerString = lists:foldl(
        fun(String, Acc) ->
            if length(String) > Acc -> length(String);
            true -> Acc
            end
        end,
        0,
        Content
    ),
    MinMessageLength = 40,

    if LongerString > MinMessageLength ->
        RealMessageLength = LongerString;
    true ->
        RealMessageLength = MinMessageLength
    end,
    ?MODULE:print_centered_rectangle(Content, RealMessageLength)
.

print_centered_rectangle(Content, RealMessageLength) ->    
    utils:print("+" ++ lists:duplicate(RealMessageLength, $-) ++ "+~n"),

    lists:foreach(
        fun(String) ->
            utils:print("|" ++ ?MODULE:center(String, RealMessageLength) ++ "|~n")
        end,
        Content
    ),

    utils:print("+" ++ lists:duplicate(RealMessageLength, $-) ++ "+~n"),
    RealMessageLength
.

% Debugging function to print the routing table of the node.
% The routing table has to be passed as a list of tuples
% as the output of ets:tab2list.
% The function prints the routing table in a formatted way.
print_routing_table(Pid) when is_pid(Pid) ->
    {ok,RoutingTable} = node:get_routing_table(Pid),
    ?MODULE:print_routing_table(RoutingTable)
;
print_routing_table(RoutingTableToList) when is_list(RoutingTableToList) ->
    RoutingTable = lists:sort(
        fun({Key1, _}, {Key2, _}) -> 
            Key1 < Key2
        end,
        RoutingTableToList
    ),
    % Getting the longest column and the longest element in the table
    {CellWidth,LongerColumn} = lists:foldl(
        fun({Key, List}, Acc) ->
            FormattedKey = lists:flatten(io_lib:format("~p", [Key])),
            KeyLen = length(FormattedKey),

            LongerInList = lists:foldl(
                fun(Element, Acc2) ->
                    FormattedElement = lists:flatten(io_lib:format("~p", [Element])),
                    ElementLen = length(FormattedElement),
                    if ElementLen > Acc2 -> 
                        ElementLen;
                    true -> Acc2
                    end
                end,
                0,
                List
            ),

            if KeyLen > LongerInList -> CurrentLonger = KeyLen;
            true -> CurrentLonger = LongerInList
            end,
            
            {LastLonger, LastListLen} = Acc, 
            if CurrentLonger > LastLonger -> 
                CellWidth = CurrentLonger;
            true -> 
                CellWidth = LastLonger
            end,
            
            ListLen = length(List),
            if ListLen > LastListLen -> 
                ReturnListLen = ListLen;
            true ->
                ReturnListLen = LastListLen
            end,
            {CellWidth, ReturnListLen}

        end,
        {0,0},
        RoutingTable
    ),

    CellTableWidth = CellWidth + 2,

    % Printing column names
    io:format("+"),
    lists:foreach(
        fun({_,_}) ->
            io:format(lists:duplicate(CellTableWidth, $-) ++ "+")
        end,
        RoutingTable    
    ),
    io:format("~n|"),
    lists:foreach(
        fun({Column,_}) ->
            io:format(center(lists:flatten(io_lib:format("~p",[Column])), CellTableWidth)++"|")
        end,
        RoutingTable    
    ),
    io:format("~n+"),
    lists:foreach(
        fun({_,_}) ->
            io:format(lists:duplicate(CellTableWidth, $-) ++ "+")
        end,
        RoutingTable    
    ),
    io:format("~n"),

    % Printing the routing table content
    lists:foreach(
        fun(I) ->
            io:format("|"),
            lists:foreach(
                fun({_,List}) ->
                    if I =< length(List) ->
                        Element = lists:nth(I, List),
                        FormattedElement = lists:flatten(io_lib:format("~p", [Element]));
                    true ->
                        FormattedElement = ""
                    end,
                    
                    CenteredLine = ?MODULE:center(FormattedElement, CellTableWidth),
                    io:format("~s|", [CenteredLine])
                end,
                RoutingTable    
            ),
            io:format("~n")
        end,
        lists:seq(1,LongerColumn)
    ),
    io:format("+"),
    lists:foreach(
        fun({_,_}) ->
            io:format(lists:duplicate(CellTableWidth, $-) ++ "+")
        end,
        RoutingTable    
    ),
    io:format("~n")
.

% Used to print console messages
print(Format)->
    io:format(Format).
print(Format, Data)->
    io:format(Format, Data)
.


% Verbose is used to decide if the debug_print function
% should print the text or not 
set_verbose(Verbose) ->
    put(verbose, Verbose)
.

% Used to get verbosity status
verbose() ->
    Result = get(verbose),
    if Result /= undefined ->
        Result;
    true ->
        false
    end
.

% Used to print debugging messages
% It only pints when verbosity is set to true
debug_print(Format)->
    ?MODULE:do_it_if_verbose(fun() -> utils:print("[~p]",[com:my_address()]),io:format(Format) end).
debug_print(Format, Data)->
    ?MODULE:do_it_if_verbose(fun() -> utils:print("[~p]",[com:my_address()]),io:format(Format, Data) end).
% This function implements the verbosity check
do_it_if_verbose(Fun) ->
    Verbose = ?MODULE:verbose(),
    
    if Verbose ->
        Fun();
    true -> ok
    end
.

% This function is used to print a progress bar
print_progress(ProgressRatio, PrintBar) ->
    Progress = round(ProgressRatio * 100),
    if PrintBar ->
        MaxLength = 30,
        CompletedLength = round(ProgressRatio * MaxLength),
        IncompleteLength = MaxLength - CompletedLength,
        % If the progress is 100% the arrow is not printed
        if(IncompleteLength == 0) ->
            EqualCharLength = CompletedLength,
            Arrow = "";
        true ->
            % If the progress is 0% the arrow is not printed
            % only if the progress is greater than 0
            if CompletedLength > 0 ->
                EqualCharLength = CompletedLength - 1,
                Arrow = ">";
            true ->
                EqualCharLength = 0,
                Arrow = ""
            end
        end,
        Bar = "[" ++ lists:duplicate(EqualCharLength, $=)
                ++ Arrow
                ++ lists:duplicate(IncompleteLength, $\s) 
                ++ "] ";
    true ->
        Bar = ""
    end,
    io:format("\r~s ~3B%  ", [Bar, Progress])
.