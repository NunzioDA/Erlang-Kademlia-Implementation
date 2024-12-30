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
-export([compile/0]).
-include_lib("kernel/include/file.hrl").

compile() ->
    {ok, Files} = file:list_dir("../src/"),
    ErlFiles = [filename:join("../src", File) || File <- Files, filename:extension(File) =:= ".erl"],
    lists:foreach(fun maybe_compile_file/1, ErlFiles).

maybe_compile_file(ErlFile) ->
    BeamFile = filename:join("../execution", filename:rootname(filename:basename(ErlFile)) ++ ".beam"),
    case file:read_file_info(ErlFile) of
        {ok, ErlInfo} ->
            case file:read_file_info(BeamFile) of
                {ok, BeamInfo} ->
                    % Compiling if .erl is modified
                    if
                        ErlInfo#file_info.mtime > BeamInfo#file_info.mtime ->
                            compile_file(ErlFile);
                        true ->
                            ok
                    end;
                _ ->
                    % Compiling if beam file doesn't exist
                    compile_file(ErlFile)
            end;
        _ ->
            io:format("Error reading file info for ~s~n", [ErlFile])
    end,
    BeamFile.

compile_file(F) ->
    io:format("Compiling ~s~n", [F]),
    c:c(F).
