------------------------------------------------------------------------------
--                              Ada Web Server                              --
--                                                                          --
--                            Copyright (C) 2000                            --
--                               Pascal Obry                                --
--                                                                          --
--  This library is free software; you can redistribute it and/or modify    --
--  it under the terms of the GNU General Public License as published by    --
--  the Free Software Foundation; either version 2 of the License, or (at   --
--  your option) any later version.                                         --
--                                                                          --
--  This library is distributed in the hope that it will be useful, but     --
--  WITHOUT ANY WARRANTY; without even the implied warranty of              --
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU       --
--  General Public License for more details.                                --
--                                                                          --
--  You should have received a copy of the GNU General Public License       --
--  along with this library; if not, write to the Free Software Foundation, --
--  Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.          --
--                                                                          --
--  As a special exception, if other files instantiate generics from this   --
--  unit, or you link this unit with other files to produce an executable,  --
--  this  unit  does not  by itself cause  the resulting executable to be   --
--  covered by the GNU General Public License. This exception does not      --
--  however invalidate any other reasons why the executable file  might be  --
--  covered by the  GNU Public License.                                     --
------------------------------------------------------------------------------

--  $Id$

with Ada.Strings.Unbounded;
with Ada.Streams;
with Interfaces.C;

with Sockets.Thin;

with AWS.Messages;
with AWS.Translater;
with AWS.URL;

package body AWS.Client is

   use Ada;
   use Ada.Strings.Unbounded;

   End_Section : constant String := "";

   procedure Init_Connection
     (Sock       :    out Sockets.Socket_FD;
      Method     : in     String;
      URL        : in     String;
      User       : in     String            := No_Data;
      Pwd        : in     String            := No_Data;
      Proxy      : in     String            := No_Data;
      Proxy_User : in     String            := No_Data;
      Proxy_Pwd  : in     String            := No_Data);
   --  send a header to the server eventually going through a proxy server
   --  with authentification.

   procedure Parse_Header
     (Sock              : in     Sockets.Socket_FD;
      Status            :    out Messages.Status_Code;
      Content_Length    :    out Natural;
      Content_Type      :    out Unbounded_String;
      Transfer_Encoding :    out Unbounded_String);
   --  Read server answer and set corresponding variable with the value
   --  read. Most of the field are ignored right now.

   ---------------------
   -- Init_Connection --
   ---------------------

   procedure Init_Connection
     (Sock       :    out Sockets.Socket_FD;
      Method     : in     String;
      URL        : in     String;
      User       : in     String            := No_Data;
      Pwd        : in     String            := No_Data;
      Proxy      : in     String            := No_Data;
      Proxy_User : in     String            := No_Data;
      Proxy_Pwd  : in     String            := No_Data)
   is
      function Get_Host_Name return String;
      --  returns the local hostname

      Proxy_Data, URL_Data : AWS.URL.Object;

      -------------------
      -- Get_Host_Name --
      -------------------

      function Get_Host_Name return String is
         Buffer : Interfaces.C.char_array (1 .. 100);
         Res    : Interfaces.C.int;
      begin
         Res := Sockets.Thin.C_gethostname (Buffer (1)'Address, 100);
         return Interfaces.C.To_Ada (Buffer);
      end Get_Host_Name;

   begin
      URL_Data   := AWS.URL.Parse (URL);
      Proxy_Data := AWS.URL.Parse (Proxy);

      -- Connect to server

      if Proxy = No_Data then
         Sockets.Socket (Sock, Sockets.AF_INET, Sockets.SOCK_STREAM);

         Sockets.Connect (Sock,
                          AWS.URL.Server_Name (URL_Data),
                          AWS.URL.Port (URL_Data));

         Sockets.Put_Line (Sock, Method & ' '
                           & AWS.URL.URI (URL_Data)
                           & ' ' & HTTP_Version);
         Sockets.Put_Line (Sock, "Connection: Keep-Alive");

      else
         Sockets.Socket (Sock, Sockets.AF_INET, Sockets.SOCK_STREAM);

         Sockets.Connect (Sock,
                          AWS.URL.Server_Name (Proxy_Data),
                          AWS.URL.Port (Proxy_Data));

         Sockets.Put_Line (Sock, Method & ' ' & URL & ' ' & HTTP_Version);
         Sockets.Put_Line (Sock, "Proxy-Connection: Keep-Alive");
      end if;

      Sockets.Put_Line (Sock, "Accept: text/html, */*");
      Sockets.Put_Line (Sock, "Accept-Language: fr, us");
      Sockets.Put_Line (Sock, "User-Agent: AWS/v" & Version);
      Sockets.Put_Line (Sock, "Host: " & Get_Host_Name);

      if User /= No_Data and then Pwd /= No_Data then
         Sockets.Put_Line
           (Sock, "Authorization: Basic " &
            AWS.Translater.Base64_Encode (User & ':' & Pwd));
      end if;

      if Proxy_User /= No_Data and then Proxy_Pwd /= No_Data then
         Sockets.Put_Line
           (Sock, "Proxy-Authorization: Basic " &
            AWS.Translater.Base64_Encode (Proxy_User & ':' & Proxy_Pwd));
      end if;
   end Init_Connection;

   ---------
   -- Get --
   ---------

   function Get (URL        : in String;
                 User       : in String := No_Data;
                 Pwd        : in String := No_Data;
                 Proxy      : in String := No_Data;
                 Proxy_User : in String := No_Data;
                 Proxy_Pwd  : in String := No_Data) return Response.Data
   is

      function Read_Chunk return Streams.Stream_Element_Array;
      --  read a chunk object from the stream

      Sock    : Sockets.Socket_FD;
      CT      : Unbounded_String;
      CT_Len  : Natural;
      TE      : Unbounded_String;
      Status  : Messages.Status_Code;
      Message : Unbounded_String;

      ----------------
      -- Read_Chunk --
      ----------------

      function Read_Chunk return Streams.Stream_Element_Array is

         use type Streams.Stream_Element_Array;
         use type Streams.Stream_Element_Offset;

         procedure Skip_Line;
         --  skip a line on the socket

         --  read the chunk size that is an hex number

         Size     : Streams.Stream_Element_Offset
           := Streams.Stream_Element_Offset'Value
           ("16#" & Sockets.Get_Line (Sock) & '#');

         Elements : Streams.Stream_Element_Array (1 .. Size);

         procedure Skip_Line is
            D : constant String := Sockets.Get_Line (Sock);
         begin
            null;
         end Skip_Line;

      begin
         if Size = 0 then
            Skip_Line;
            return Elements;
         else
            Sockets.Receive (Sock, Elements);
            Skip_Line;
            return Elements & Read_Chunk;
         end if;
      end Read_Chunk;

   begin
      Init_Connection (Sock, "GET",
                       URL, User, Pwd, Proxy, Proxy_User, Proxy_Pwd);

      Sockets.New_Line (Sock);

      Parse_Header (Sock, Status, CT_Len, CT, TE);

      --  read the message body

      if To_String (TE) = "chunked" then

         --  a chuncked message is written on the stream as list of data
         --  chunk. Each chunk has the following format:
         --
         --  <N : the chunk size in hexadecimal> CRLF
         --  <N * BYTES : the data> CRLF
         --
         --  The termination chunk is:
         --
         --  0 CRLF
         --  CRLF
         --

         declare
            Elements : Streams.Stream_Element_Array := Read_Chunk;
         begin
            return Response.Build (To_String (CT),
                                   Elements,
                                   Status);
         end;

      else

         declare
            Elements : Streams.Stream_Element_Array
              (1 .. Streams.Stream_Element_Offset (CT_Len));
         begin
            Sockets.Receive (Sock, Elements);
            Sockets.Shutdown (Sock);

            if CT = "text/html" then

               --  if the content is textual info put it in a string

               for K in Elements'Range loop
                  Append (Message, Character'Val (Natural (Elements (K))));
               end loop;

               return Response.Build (To_String (CT),
                                      To_String (Message),
                                      Status);
            else

               --  this is some kind of binary data.

               return Response.Build (To_String (CT),
                                      Elements,
                                      Status);
            end if;
         end;
      end if;

   exception
      when others =>
         raise URL_Error;
   end Get;

   ------------------
   -- Parse_Header --
   ------------------

   procedure Parse_Header
     (Sock              : in     Sockets.Socket_FD;
      Status            :    out Messages.Status_Code;
      Content_Length    :    out Natural;
      Content_Type      :    out Unbounded_String;
      Transfer_Encoding :    out Unbounded_String) is
   begin
      loop
         declare
            Line : constant String := Sockets.Get_Line (Sock);
         begin
            if Line = End_Section then
               exit;

            elsif Messages.Is_Match (Line, Messages.HTTP_Token) then
               Status := Messages.Status_Code'Value
                 ('S' & Line (Messages.HTTP_Token'Last + 5
                              .. Messages.HTTP_Token'Last + 7));

            elsif Messages.Is_Match (Line, Messages.Content_Type_Token) then
               Content_Type := To_Unbounded_String
                 (Line (Messages.Content_Type_Token'Last + 1 .. Line'Last));

            elsif Messages.Is_Match (Line, Messages.Content_Length_Token) then
               Content_Length := Natural'Value
                 (Line (Messages.Content_Length_Range'Last + 1 .. Line'Last));

            elsif Messages.Is_Match (Line,
                                     Messages.Transfer_Encoding_Token)
            then
               Transfer_Encoding := To_Unbounded_String
                 (Line (Messages.Transfer_Encoding_Range'Last + 1
                        .. Line'Last));

            else
               --  everything else is ignore right now
               null;
            end if;
         end;
      end loop;
   end Parse_Header;

   ---------
   -- Put --
   ---------

   function Put (URL        : in String;
                 Data       : in String;
                 User       : in String := No_Data;
                 Pwd        : in String := No_Data;
                 Proxy      : in String := No_Data;
                 Proxy_User : in String := No_Data;
                 Proxy_Pwd  : in String := No_Data) return Response.Data
   is
      Sock    : Sockets.Socket_FD;
      CT      : Unbounded_String;
      CT_Len  : Natural;
      TE      : Unbounded_String;
      Status  : Messages.Status_Code;
   begin
      Init_Connection (Sock, "PUT",
                       URL, User, Pwd, Proxy, Proxy_User, Proxy_Pwd);

      --  send message Content_Length

      Sockets.Put_Line (Sock, Messages.Content_Length (Data'Length));

      Sockets.New_Line (Sock);

      --  send message body

      Sockets.Put_Line (Sock, Data);

      --  get answer from server

      Parse_Header (Sock, Status, CT_Len, CT, TE);

      return Response.Acknowledge (Status);
   end Put;

end AWS.Client;
