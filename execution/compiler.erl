% -----------------------------------------------------------------------------
% Module: compiler
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2013-01-15
% Description: This module compiles the source files in the src directory.
% Usage: c(compiler). compiler:compile().
% -----------------------------------------------------------------------------
% The compile/0 function compiles the source files in the src directory.
% The compile_file/1 function compiles a single file.
% -----------------------------------------------------------------------------

-module(compiler).
-export([compile/0, find_erl_files/1, list_dirs_and_files/1, maybe_compile_file/1, compile_file/1]).
-export([is_directory/2, process_entry/1]).
-include_lib("kernel/include/file.hrl").

% This function compiles all .erl files 
% in the src directory and its subdirectories
compile() ->
    ErlFiles = ?MODULE:find_erl_files("../src/"),
    lists:foreach(fun ?MODULE:maybe_compile_file/1, ErlFiles).

% This function compiles a file if it is newer 
% than the corresponding beam file or if the 
% beam file doesn't exist
maybe_compile_file(ErlFile) ->
    BeamFile = filename:join("../execution", filename:rootname(filename:basename(ErlFile)) ++ ".beam"),
    case file:read_file_info(ErlFile) of
        {ok, ErlInfo} ->
            case file:read_file_info(BeamFile) of
                {ok, BeamInfo} ->
                    % Compiling if .erl is modified
                    if
                        ErlInfo#file_info.mtime > BeamInfo#file_info.mtime ->
                            ?MODULE:compile_file(ErlFile);
                        true ->
                            ok
                    end;
                _ ->
                    % Compiling if beam file doesn't exist
                    ?MODULE:compile_file(ErlFile)
            end;
        _ ->
            io:format("Error reading file info for ~s~n", [ErlFile])
    end,
    BeamFile.

% This function compiles a single file
% It prints a message before compiling the file
compile_file(F) ->
    io:format("Compiling ~s~n", [F]),
    c:c(F).

% --------------------------------------------
% Managing directories and files
% --------------------------------------------
%
% This function Recursively finds all .erl files in a directory
find_erl_files(Dir) ->
    case ?MODULE:list_dirs_and_files(Dir) of
        {ok, Entries} ->
            lists:flatmap(fun ?MODULE:process_entry/1, [filename:join(Dir, Entry) || Entry <- Entries]);
        {error, Reason} ->
            io:format("Error reading directory ~s: ~p~n", [Dir, Reason]),
            []
    end.

% This function processes a directory entry
% If the entry is a directory, it recursively processes it
% If the entry is a .erl file, it returns a list containing the file path
process_entry(Path) ->
    PathExt = filename:extension(Path),
    case file:read_file_info(Path) of
        {ok, #file_info{type = directory}} ->
            ?MODULE:find_erl_files(Path); % Recursively process subdirectories
        {ok, #file_info{type = regular}} when PathExt =:= ".erl" ->
            [Path];
        _ ->
            []
    end.

% This function lists directories and files in a directory
% It returns the directories first, then the files
list_dirs_and_files(Path) ->
    case file:list_dir(Path) of
        {ok, Items} ->
            % Ottieni informazioni su ciascun elemento
            Directories = [Item || Item <- Items, ?MODULE:is_directory(Path, Item)],
            Files = [Item || Item <- Items, not ?MODULE:is_directory(Path, Item)],
            {ok, Directories ++ Files};
        Error -> 
            Error
    end.

% This function checks if an item is a directory
-spec is_directory(BasePath :: string(), Item :: string()) -> boolean().
is_directory(BasePath, Item) ->
    case file:read_file_info(filename:join(BasePath, Item)) of
        {ok, #file_info{type = directory}} -> true;
        _ -> false
    end.


