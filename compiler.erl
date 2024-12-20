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

- module(compiler).
- export([compile/0]).

compile() ->
    Files = ["src/starter.erl", "src/node.erl"],
    lists:foreach(fun(F) -> compile_file(F) end, Files).

compile_file(F) ->
    io:format("~p~n", [c:c(F)]).