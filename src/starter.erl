% -----------------------------------------------------------------------------
% Module: starter
% Author(s): Nunzio D'Amore, Francesco Rossi
% Date: 2013-01-15
% Description: This module starts the kademlia network simulation.
% -----------------------------------------------------------------------------

- module(starter).

- export([start/0]).
- import(node, [talk/0]).

start() -> node:talk().