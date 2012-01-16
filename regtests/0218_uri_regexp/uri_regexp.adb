------------------------------------------------------------------------------
--                              Ada Web Server                              --
--                                                                          --
--                     Copyright (C) 2011-2012, AdaCore                     --
--                                                                          --
--  This is free software;  you can redistribute it  and/or modify it       --
--  under terms of the  GNU General Public License as published  by the     --
--  Free Software  Foundation;  either version 3,  or (at your option) any  --
--  later version.  This software is distributed in the hope  that it will  --
--  be useful, but WITHOUT ANY WARRANTY;  without even the implied warranty --
--  of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU     --
--  General Public License for  more details.                               --
--                                                                          --
--  You should have  received  a copy of the GNU General  Public  License   --
--  distributed  with  this  software;   see  file COPYING3.  If not, go    --
--  to http://www.gnu.org/licenses for a complete copy of the license.      --
------------------------------------------------------------------------------

with Ada.Text_IO;

with AWS.Client;
with AWS.Config.Set;
with AWS.Dispatchers.Callback;
with AWS.Server;
with AWS.Services.Dispatchers.URI;
with AWS.Status;
with AWS.Response;
with AWS.Utils;

with Get_Free_Port;

procedure URI_Regexp is

   use Ada;
   use AWS;
   use AWS.Services;

   Cfg       : Config.Object;
   Free_Port : Positive := 1295;

   function CB1 (Request : AWS.Status.Data) return AWS.Response.Data is
      pragma Unreferenced (Request);
   begin
      return AWS.Response.Build ("text/html", "Dispatch 1 !");
   end CB1;

   function CB2 (Request : AWS.Status.Data) return AWS.Response.Data is
      pragma Unreferenced (Request);
   begin
      return AWS.Response.Build ("text/html", "Dispatch 2 !");
   end CB2;

   function Default (Request : AWS.Status.Data) return AWS.Response.Data is
      URI : constant String := Status.URI (Request);
   begin
      return AWS.Response.Build ("text/html", "Default " & URI);
   end Default;

   procedure Test (URI : String) is
      R : Response.Data;
   begin
      Text_IO.Put_Line (URI);
      R := Client.Get
        ("http://localhost:" & AWS.Utils.Image (Free_Port) & URI);
      Text_IO.Put_Line ("> " & Response.Message_Body (R));
   end Test;

   H  : AWS.Services.Dispatchers.URI.Handler;

   WS : AWS.Server.HTTP;

begin
   Services.Dispatchers.URI.Register_Regexp
     (H, "/template/.*", CB1'Unrestricted_Access);

   Services.Dispatchers.URI.Register_Regexp
     (H, "/site/template/.*", CB2'Unrestricted_Access);

   Services.Dispatchers.URI.Register_Default_Callback
     (H, AWS.Dispatchers.Callback.Create (Default'Unrestricted_Access));

   Get_Free_Port (Free_Port);
   AWS.Config.Set.Server_Port (Cfg, Free_Port);

   AWS.Server.Start (WS, Dispatcher => H, Config => Cfg);

   Test ("/site/template/xxx");

   --  Close servers

   AWS.Server.Shutdown (WS);
end URI_Regexp;