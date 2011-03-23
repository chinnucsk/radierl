%%% $Id$
%%%---------------------------------------------------------------------
%%% @copyright 2011 Motivity Telecom
%%% @author Vance Shipley <vances@motivity.ca> [http://www.motivity.ca]
%%% @end
%%%
%%% Copyright (c) 2011, Motivity Telecom
%%% 
%%% All rights reserved.
%%% 
%%% Redistribution and use in source and binary forms, with or without
%%% modification, are permitted provided that the following conditions
%%% are met:
%%% 
%%%    - Redistributions of source code must retain the above copyright
%%%      notice, this list of conditions and the following disclaimer.
%%%    - Redistributions in binary form must reproduce the above copyright
%%%      notice, this list of conditions and the following disclaimer in
%%%      the documentation and/or other materials provided with the 
%%%      distribution.
%%%    - Neither the name of Motivity Telecom nor the names of its
%%%      contributors may be used to endorse or promote products derived
%%%      from this software without specific prior written permission.
%%%
%%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
%%% "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
%%% LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
%%% A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
%%% OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
%%% SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
%%% LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
%%% DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
%%% THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT 
%%% (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
%%% OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
%%%
%%%---------------------------------------------------------------------
%%% @doc This {@link //radius/radius. radius} behaviour module
%%%	implements an example call back module for accounting
%%%	in the {@link //radius. radius} application.
%%%
-module(radius_example_accounting).
-copyright('Copyright (c) 2011 Motivity Telecom').
-author('vances@motivity.ca').
-vsn('$Revision$').

-behaviour(radius).

%% export the radius behaviour callbacks
-export([init/2, request/3, terminate/1]).

%% @headerfile "../../include/radius.hrl"
-include("radius.hrl").

-define(LOGNAME, radius_acct).

%%----------------------------------------------------------------------
%%  The radius callbacks
%%----------------------------------------------------------------------

%% @spec (Address, Port) -> Result
%% 	Address = ip_address()
%% 	Port = integer()
%% 	 Result = ok | {error, Reason}
%% 	Reason = term()
%% @doc This callback function is called when a
%% 	{@link //radius/radius_server. radius_server} behaviour process
%% 	initializes.
%%
init(_Address, _Port) ->
	{ok, Directory} = application:get_env(radius_example, accounting_dir),
	Log = ?LOGNAME,
	FileName = Directory ++ "/" ++ atom_to_list(Log),
	case disk_log:open([{name, Log}, {file, FileName},
			{type, wrap}, {size, {1048575, 20}}]) of
		{ok, Log} ->
			ok;
		{repaired, Log, {recovered, Rec}, {badbytes, Bad}} ->
			error_logger:warning_report(["Disk log repaired",
					{log, Log}, {path, FileName}, {recovered, Rec},
					{badbytes, Bad}]),
			ok;
		{error, Reason} ->
			{error, Reason}
	end.

%% @spec (Address, Port, Packet) -> Result
%% 	Address = ip_address()
%% 	Port = integer()
%% 	Packet = binary()
%% 	Result = binary() | {error, Reason}
%% 	Reason = ignore | term()
%% @doc This callback function is called when a request is received
%% 	on the port.
%%
request(Address, _Port, Packet) ->
	case radius_example:find_client(Address) of
		{ok, Secret} ->
			request(Packet, Secret);
		error ->
			{error, ignore}
	end.
%% @hidden
request(<<_Code, Id, Length:16, _/binary>> = Packet, Secret) ->
	try
		#radius{code = ?AccountingRequest, id = Id,
				authenticator = Authenticator,
				attributes = BinaryAttributes} = radius:codec(Packet),
		Attributes = radius_attributes:codec(BinaryAttributes),
		NasIpAddressV = radius_attributes:find(?NasIpAddress, Attributes),
		NasIdentifierV = radius_attributes:find(?NasIdentifier, Attributes),
		case {NasIpAddressV, NasIdentifierV} of
			{error, error} ->
				throw(reject);
			{_, _} ->
				ok
		end,
		error = radius_attributes:find(?UserPassword, Attributes),
		error = radius_attributes:find(?ChapPassword, Attributes),
		error = radius_attributes:find(?ReplyMessage, Attributes),
		error = radius_attributes:find(?State, Attributes),
		{ok, _AcctSessionId} = radius_attributes:find(?AcctSessionId, Attributes),
		Hash = erlang:md5([<<?AccountingRequest, Id, Length:16, 0:128>>,
				BinaryAttributes, Secret]),
		Authenticator = binary_to_list(Hash),
		case disk_log:log(?LOGNAME, Attributes) of
			ok ->
				response(Id, Authenticator, Secret, []);
			{error, _Reason} ->
				{error, ignore}
		end
	catch
		_:_ ->
			{error, ignore}
	end.

%% @spec (Reason) -> ok
%% 	Reason = term()
%% @doc This callback function is called just before the server exits.
%%
terminate(_Reason) ->
	disk_log:close(?LOGNAME).

%%----------------------------------------------------------------------
%%  internal functions
%%----------------------------------------------------------------------

%% @spec (Id, RequestAuthenticator, Secret, Attributes) -> AccessAccept
%% @hidden
response(Id, RequestAuthenticator, Secret, AttributeList)
		when is_list(AttributeList) ->
	Attributes = radius_attributes:codec(AttributeList),
	response(Id, RequestAuthenticator, Secret, Attributes);
response(Id, RequestAuthenticator, Secret, Attributes)
		when is_binary(Attributes) ->
	Length = size(Attributes) + 20,
	ResponseAuthenticator = erlang:md5([<<?AccountingResponse, Id, Length:16>>,
			RequestAuthenticator, Attributes, Secret]),
	Response = #radius{code = ?AccountingResponse, id = Id,
			authenticator = ResponseAuthenticator, attributes = Attributes},
	radius:codec(Response).
