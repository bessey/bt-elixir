defmodule Bittorrent.PeerCommunication do
  @pstr "BitTorrent protocol"
  @pstrlen String.length(@pstr)
  alias Bittorrent.{Peer, Torrent}

  @msg_choke 0
  @msg_unchoke 1
  @msg_interested 2
  @msg_not_interested 3
  @msg_have 4
  @msg_bitfield 5
  @msg_request 6
  @msg_piece 7
  @msg_cancel 8

  def connect_to_peer({ip, port}, torrent_info, peer_id) do
    IO.puts("Connecting: #{to_string(ip)} #{port}")

    case :gen_tcp.connect(ip, port, [:binary, packet: :raw, active: false], 3000) do
      {:error, error} ->
        {:error, error}

      {:ok, socket} ->
        send_handshake(torrent_info, peer_id, socket)
    end
  end

  def receive_loop(peer, torrent_info, socket) do
    case :gen_tcp.recv(socket, 4) do
      {:error, :enotconn} ->
        IO.puts("Error: Not Conn")

      {:error, :closed} ->
        IO.puts("Error: Closed")

      {:ok, <<msg_length::unsigned-integer-size(32)>>} ->
        peer = receive_message(peer, torrent_info, msg_length, socket)
        peer = send_loop(peer, socket)
        receive_loop(peer, torrent_info, socket)
    end
  end

  def send_loop(%Peer{choking: true} = peer, socket) do
    send_unchoke(peer, socket)
  end

  def send_loop(%Peer{choked: false} = peer, socket) do
    if request = Bittorrent.Downloader.request_block(peer.pieces) do
      peer =
        if peer.interested_in do
          peer
        else
          send_interested(peer, socket)
        end

      send_request(peer, socket, request)
    else
      send_not_interested(peer, socket)
    end
  end

  def send_loop(peer, _socket), do: peer

  # Receive Protocols

  defp receive_message(peer, _torrent_info, 0, __socket) do
    puts(peer, "Keep Alive")
    peer
  end

  defp receive_message(peer, torrent_info, length, socket) do
    id = receive_message_id(socket)
    process_message(peer, torrent_info, id, length, socket)
  end

  defp process_message(peer, _torrent_info, @msg_choke, 1, _socket) do
    puts(peer, "Msg: choke")
    %Peer{peer | choked: true}
  end

  defp process_message(peer, _torrent_info, @msg_unchoke, 1, _socket) do
    puts(peer, "Msg: unchoke")
    %Peer{peer | choked: false}
  end

  defp process_message(peer, _torrent_info, @msg_interested, 1, _socket) do
    puts(peer, "Msg: interested")
    %Peer{peer | interested: true, choked: false}
  end

  defp process_message(peer, _torrent_info, @msg_not_interested, 1, _socket) do
    puts(peer, "Msg: not interested")
    %Peer{peer | interested: false, choked: false}
  end

  defp process_message(peer, _torrent_info, @msg_have, 5 = length, socket) do
    case :gen_tcp.recv(socket, length - 1) do
      {:ok, <<piece::unsigned-integer-size(32)>>} ->
        puts(peer, "Msg: have #{piece}")
        %Peer{Peer.have_piece(peer, piece) | choked: false}
    end
  end

  defp process_message(peer, _torrent_info, @msg_bitfield, length, socket) do
    puts(peer, "Msg: bitfield #{length}")

    case :gen_tcp.recv(socket, length - 1) do
      {:ok, <<bitfield::bits>>} ->
        %Peer{peer | pieces: Torrent.bitfield_pieces(bitfield), choked: false}
    end
  end

  defp process_message(peer, _torrent_info, @msg_request, 13, _socket) do
    puts(peer, "Msg: request")
    peer
  end

  defp process_message(peer, _torrent_info, @msg_piece, length, socket) do
    case :gen_tcp.recv(socket, length - 1) do
      {:ok,
       <<
         block::unsigned-integer-size(32),
         _begin::unsigned-integer-size(32),
         data::binary
       >>} ->
        puts(peer, "Msg: piece #{block}")
        Bittorrent.Downloader.block_downloaded(block, data)
        peer
    end

    peer
  end

  defp process_message(peer, _torrent_info, @msg_cancel, 13, _socket) do
    puts(peer, "Msg: cancel")
    peer
  end

  defp process_message(peer, _torrent_info, id, length, _socket) do
    puts(peer, "Msg: unknown id: #{id}, length: #{length}")
    raise "Stopping because unknown"
    peer
  end

  defp receive_message_id(socket) do
    {:ok, <<msg_id::unsigned-integer-size(8)>>} = :gen_tcp.recv(socket, 1)
    msg_id
  end

  defp receive_handshake(socket, torrent_info) do
    case :gen_tcp.recv(socket, 1) do
      {:error, :closed} ->
        IO.puts("Conn: Closed")

      {:ok, <<pstr_length::unsigned-integer-size(8)>>} ->
        base_length = 48

        {
          :ok,
          <<
            pstr::binary-size(pstr_length),
            reserved::unsigned-integer-size(64),
            info_hash::binary-size(20),
            peer_id::binary-size(20)
          >>
        } = :gen_tcp.recv(socket, base_length + pstr_length)

        IO.puts("Connected: #{Base.encode64(peer_id)}")

        %Peer{
          name: to_string(pstr),
          reserved: reserved,
          info_hash: info_hash,
          id: peer_id,
          # Assume new peers have nothing until we know otherwise
          pieces: Torrent.empty_pieces(torrent_info)
        }
    end
  end

  # Send Protocols

  defp send_handshake(torrent_info, peer_id, socket) do
    handshake = handshake_message(torrent_info.info_sha, peer_id)
    :ok = :gen_tcp.send(socket, handshake)
    peer = receive_handshake(socket, torrent_info)
    {:ok, peer, socket}
  end

  defp send_request(peer, socket, {block, begin, block_size}) do
    puts(peer, "Send: request #{block}")

    :ok =
      :gen_tcp.send(socket, <<
        13::unsigned-integer-size(32),
        @msg_request::unsigned-integer-size(8),
        block::unsigned-integer-size(32),
        begin::unsigned-integer-size(32),
        block_size::unsigned-integer-size(32)
      >>)

    peer
  end

  defp send_interested(peer, socket) do
    puts(peer, "Send: interested")

    :ok =
      :gen_tcp.send(
        socket,
        <<1::unsigned-integer-size(32), @msg_interested::unsigned-integer-size(8)>>
      )

    %Peer{peer | interested_in: true}
  end

  defp send_not_interested(peer, socket) do
    puts(peer, "Send: not interested")

    :ok =
      :gen_tcp.send(
        socket,
        <<1::unsigned-integer-size(32), @msg_not_interested::unsigned-integer-size(8)>>
      )

    %Peer{peer | interested_in: false}
  end

  defp send_unchoke(peer, socket) do
    puts(peer, "Send: unchoke")

    :ok =
      :gen_tcp.send(
        socket,
        <<1::unsigned-integer-size(32), @msg_unchoke::unsigned-integer-size(8)>>
      )

    %Peer{peer | choking: false}
  end

  defp send_choke(peer, socket) do
    puts(peer, "Send: choke")

    :ok =
      :gen_tcp.send(
        socket,
        <<1::unsigned-integer-size(32), @msg_choke::unsigned-integer-size(8)>>
      )

    %Peer{peer | choking: true}
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
end
