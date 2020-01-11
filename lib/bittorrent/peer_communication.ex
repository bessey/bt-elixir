defmodule Bittorrent.PeerCommunication do
  @pstr "BitTorrent protocol"
  @pstrlen String.length(@pstr)
  alias Bittorrent.{Peer, Torrent, Piece}

  def connect_to_peer({ip, port}, torrent_info, peer_id) do
    IO.puts("Connecting: #{to_string(ip)} #{port}")

    case :gen_tcp.connect(ip, port, [:binary, packet: :raw, active: false], 3000) do
      {:error, error} ->
        {:error, error}

      {:ok, socket} ->
        handshake = handshake_message(torrent_info.info_sha, peer_id)
        :ok = :gen_tcp.send(socket, handshake)
        peer = receive_handshake(socket, torrent_info)
        {:ok, peer, socket}
    end
  end

  def receive_loop(peer, torrent_info, socket) do
    case :gen_tcp.recv(socket, 4) do
      {:error, :enotconn} ->
        IO.puts("Error: Not Conn")

      {:ok, <<msg_length::unsigned-integer-size(32)>>} ->
        peer = receive_message(peer, torrent_info, msg_length, socket)
        receive_loop(peer, torrent_info, socket)
    end
  end

  defp receive_message(_peer, _torrent_info, 0, __socket) do
    IO.puts("Keep Alive")
  end

  defp receive_message(peer, torrent_info, length, socket) do
    id = receive_message_id(socket)
    process_message(peer, torrent_info, id, length, socket)
  end

  defp process_message(peer, _torrent_info, 0, 1, _socket) do
    IO.puts("Msg: choke")
    peer
  end

  defp process_message(peer, _torrent_info, 1, 1, _socket) do
    IO.puts("Msg: unchoke")
    peer
  end

  defp process_message(peer, _torrent_info, 2, 1, _socket) do
    IO.puts("Msg: interested")
    peer
  end

  defp process_message(peer, _torrent_info, 3, 1, _socket) do
    IO.puts("Msg: not interested")
    peer
  end

  defp process_message(peer, _torrent_info, 4, 5, _socket) do
    IO.puts("Msg: have")
    peer
  end

  defp process_message(peer, _torrent_info, 5, length, socket) do
    IO.puts("Msg: bitfield #{length}")
    length_rem = length - 1

    case :gen_tcp.recv(socket, length_rem) do
      {:ok, <<bitfield::bits>>} ->
        %Peer{peer | pieces: Piece.update_with_bitfield(peer.pieces, bitfield)}
    end
  end

  defp process_message(peer, _torrent_info, 6, 13, _socket) do
    IO.puts("Msg: request")
    peer
  end

  defp process_message(peer, _torrent_info, 7, _length, _socket) do
    IO.puts("Msg: piece")
    peer
  end

  defp process_message(peer, _torrent_info, 8, 13, _socket) do
    IO.puts("Msg: cancel")
    peer
  end

  defp process_message(peer, _torrent_info, id, length, _socket) do
    IO.puts("Msg: unknown id: #{id}, length: #{length}")
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
        pstr_length_bytes = 8 * pstr_length
        base_length = 48

        {
          :ok,
          <<
            pstr::size(pstr_length_bytes),
            reserved::unsigned-integer-size(64),
            info_hash::size(160),
            peer_id::size(160)
          >>
        } = :gen_tcp.recv(socket, base_length + pstr_length)

        %Peer{
          name: pstr,
          reserved: reserved,
          info_hash: info_hash,
          peer_id: peer_id,
          # Assume new peers have nothing until we know otherwise
          pieces: Torrent.empty_pieces(torrent_info)
        }
    end
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
end
