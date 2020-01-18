defmodule Bittorrent.Peer.Protocol do
  @pstr "BitTorrent protocol"
  @pstrlen String.length(@pstr)
  alias Bittorrent.{Peer.State, Torrent}

  @msg_choke 0
  @msg_unchoke 1
  @msg_interested 2
  @msg_not_interested 3
  @msg_have 4
  @msg_bitfield 5
  @msg_request 6
  @msg_piece 7
  @msg_cancel 8

  @max_requests_in_flight 10

  def connect_to_peer({ip, port}, info_sha, peer_id, pieces_count) do
    IO.puts("Connecting: #{to_string(ip)} #{port}")

    with {:ok, socket} <-
           :gen_tcp.connect(ip, port, [:binary, packet: :raw, active: false], 3000),
         {:ok, peer} <-
           send_and_receive_handshake(info_sha, peer_id, pieces_count, ip, port, socket) do
      {:ok, peer, socket}
    else
      error -> error
    end
  end

  def run_loop(peer, socket) do
    case :gen_tcp.recv(socket, 4) do
      {:error, :enotconn} ->
        IO.puts("Error: Not Conn")

      {:error, :closed} ->
        IO.puts("Error: Closed")

      {:ok, <<msg_length::unsigned-integer-size(32)>>} ->
        peer
        |> receive_message(msg_length, socket)
        |> send_loop(socket)
        |> run_loop(socket)
    end
  end

  def send_loop(%State{choking: true} = peer, socket) do
    send_unchoke(peer, socket)
  end

  def send_loop(%State{choked: false} = peer, socket) do
    if request = Bittorrent.Downloader.request_block(peer.pieces) do
      peer =
        if peer.interested_in do
          peer
        else
          send_interested(peer, socket)
        end

      if peer.requests_in_flight < @max_requests_in_flight do
        send_request_and_loop(peer, socket, request)
      else
        peer
      end
    else
      send_not_interested(peer, socket)
    end
  end

  def send_loop(peer, _socket), do: peer

  defp send_request_and_loop(peer, socket, request) do
    peer = send_request(peer, socket, request)

    if peer.requests_in_flight < @max_requests_in_flight do
      request = Bittorrent.Downloader.request_block(peer.pieces)
      send_request_and_loop(peer, socket, request)
    else
      peer
    end
  end

  # Receive Protocols

  defp receive_message(peer, 0, __socket) do
    puts(peer, "Keep Alive")
    peer
  end

  defp receive_message(peer, length, socket) do
    id = receive_message_id(socket)
    process_message(peer, id, length, socket)
  end

  defp process_message(peer, @msg_choke, 1, _socket) do
    puts(peer, "Msg: choke")
    %State{peer | choked: true}
  end

  defp process_message(peer, @msg_unchoke, 1, _socket) do
    puts(peer, "Msg: unchoke")
    %State{peer | choked: false}
  end

  defp process_message(peer, @msg_interested, 1, _socket) do
    puts(peer, "Msg: interested")
    %State{peer | interested: true, choked: false}
  end

  defp process_message(peer, @msg_not_interested, 1, _socket) do
    puts(peer, "Msg: not interested")
    %State{peer | interested: false, choked: false}
  end

  defp process_message(peer, @msg_have, 5 = length, socket) do
    case :gen_tcp.recv(socket, length - 1) do
      {:ok, <<piece::unsigned-integer-size(32)>>} ->
        puts(peer, "Msg: have #{piece}")
        %State{State.have_piece(peer, piece) | choked: false}
    end
  end

  defp process_message(peer, @msg_bitfield, length, socket) do
    puts(peer, "Msg: bitfield #{length}")

    case :gen_tcp.recv(socket, length - 1) do
      {:ok, <<bitfield::bits>>} ->
        %State{peer | pieces: Torrent.bitfield_pieces(bitfield), choked: false}
    end
  end

  defp process_message(peer, @msg_request, 13, _socket) do
    puts(peer, "Msg: request")
    peer
  end

  defp process_message(peer, @msg_piece, length, socket) do
    case :gen_tcp.recv(socket, length - 1) do
      {:ok,
       <<
         piece_index::unsigned-integer-size(32),
         begin::unsigned-integer-size(32),
         data::binary
       >>} ->
        puts(peer, "Msg: piece #{piece_index}")
        Bittorrent.Downloader.block_downloaded(piece_index, begin, data)
        %State{peer | requests_in_flight: peer.requests_in_flight - 1}
    end
  end

  defp process_message(peer, @msg_cancel, 13, _socket) do
    puts(peer, "Msg: cancel")
    peer
  end

  defp process_message(peer, id, length, _socket) do
    puts(peer, "Msg: unknown id: #{id}, length: #{length}")
    raise "Stopping because unknown"
    peer
  end

  defp receive_message_id(socket) do
    {:ok, <<msg_id::unsigned-integer-size(8)>>} = :gen_tcp.recv(socket, 1)
    msg_id
  end

  defp receive_handshake(socket, ip, port, pieces_count) do
    base_length = 48

    with {:ok, <<pstr_length::unsigned-integer-size(8)>>} <- :gen_tcp.recv(socket, 1),
         {
           :ok,
           <<
             pstr::binary-size(pstr_length),
             reserved::unsigned-integer-size(64),
             info_hash::binary-size(20),
             peer_id::binary-size(20)
           >>
         } <- :gen_tcp.recv(socket, base_length + pstr_length) do
      IO.puts("Connected: #{Base.encode64(peer_id)}")

      {:ok,
       %State{
         name: to_string(pstr),
         ip: ip,
         port: port,
         reserved: reserved,
         info_hash: info_hash,
         id: peer_id,
         # Assume new peers have nothing until we know otherwise
         pieces: empty_pieces(pieces_count)
       }}
    else
      error -> error
    end
  end

  # Send Protocols

  defp send_and_receive_handshake(info_sha, peer_id, pieces_count, ip, port, socket) do
    handshake = handshake_message(info_sha, peer_id)
    :ok = :gen_tcp.send(socket, handshake)
    receive_handshake(socket, ip, port, pieces_count)
  end

  defp send_request(peer, socket, {block, begin, block_size}) do
    puts(
      peer,
      "Send: request #{block} (#{peer.requests_in_flight + 1} / #{@max_requests_in_flight}"
    )

    :ok =
      :gen_tcp.send(socket, <<
        13::unsigned-integer-size(32),
        @msg_request::unsigned-integer-size(8),
        block::unsigned-integer-size(32),
        begin::unsigned-integer-size(32),
        block_size::unsigned-integer-size(32)
      >>)

    %State{peer | requests_in_flight: peer.requests_in_flight + 1}
  end

  defp send_interested(peer, socket) do
    puts(peer, "Send: interested")

    :ok =
      :gen_tcp.send(
        socket,
        <<1::unsigned-integer-size(32), @msg_interested::unsigned-integer-size(8)>>
      )

    %State{peer | interested_in: true}
  end

  defp send_not_interested(peer, socket) do
    puts(peer, "Send: not interested")

    :ok =
      :gen_tcp.send(
        socket,
        <<1::unsigned-integer-size(32), @msg_not_interested::unsigned-integer-size(8)>>
      )

    %State{peer | interested_in: false}
  end

  defp send_unchoke(peer, socket) do
    puts(peer, "Send: unchoke")

    :ok =
      :gen_tcp.send(
        socket,
        <<1::unsigned-integer-size(32), @msg_unchoke::unsigned-integer-size(8)>>
      )

    %State{peer | choking: false}
  end

  defp send_choke(peer, socket) do
    puts(peer, "Send: choke")

    :ok =
      :gen_tcp.send(
        socket,
        <<1::unsigned-integer-size(32), @msg_choke::unsigned-integer-size(8)>>
      )

    %State{peer | choking: true}
  end

  # handshake: <pstrlen><pstr><reserved><info_hash><peer_id>
  #
  # pstrlen: string length of <pstr>, as a single raw byte
  # pstr: string identifier of the protocol
  # reserved: eight (8) reserved bytes. All current implementations use all zeroes. Each bit in these bytes can be used to change the behavior of the protocol. An email from Bram suggests that trailing bits should be used first, so that leading bits may be used to change the meaning of trailing bits.
  # info_hash: 20-byte SHA1 hash of the info key in the metainfo file. This is the same info_hash that is transmitted in tracker requests.
  # peer_id: 20-byte string used as a unique ID for the client. This is usually the same peer_id that is transmitted in tracker requests (but not always e.g. an anonymity option in Azureus).
  defp handshake_message(info_hash, peer_id) do
    <<
      @pstrlen,
      @pstr,
      0::unsigned-integer-size(64),
      info_hash::binary,
      peer_id::binary
    >>
  end

  defp puts(peer, message) do
    IO.puts(message <> " [#{Base.encode64(peer.id)}]")
  end

  defp empty_pieces(pieces_count) do
    List.duplicate(false, pieces_count)
  end
end
