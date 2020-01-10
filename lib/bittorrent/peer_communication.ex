defmodule Bittorrent.PeerCommunication do
  @pstr "BitTorrent protocol"
  @pstrlen String.length(@pstr)

  defmodule Peer do
    defstruct [:name, :reserved, :info_hash, :peer_id]
  end

  def connect_to_peer({ip, port}, info_hash, peer_id) do
    IO.puts("Connecting: #{to_string(ip)} #{port}")

    case :gen_tcp.connect(ip, port, [:binary, packet: :raw, active: false], 3000) do
      {:error, :econnrefused} ->
        IO.puts("Conn: Refused")

      {:error, :timeout} ->
        IO.puts("Conn: Timeout")

      {:ok, socket} ->
        handshake = handshake_message(info_hash, peer_id)
        :ok = :gen_tcp.send(socket, handshake)
        receive_handshake(socket)
    end
  end

  def receive_loop(socket) do
    {:ok, <<msg_length::unsigned-integer-size(32)>>} = :gen_tcp.recv(socket, 4)
    receive_message(msg_length, socket)
  end

  defp receive_message(0, _socket) do
    IO.puts("Keep Alive")
  end

  defp receive_message(length, socket) do
    id = receive_message_id(socket)
    IO.puts("Received message #{id}")
    receive_useful_message(id, length, socket)
  end

  defp receive_useful_message(0, 1, socket) do
    IO.puts("Msg: choke")
  end

  defp receive_useful_message(1, 1, socket) do
    IO.puts("Msg: unchoke")
  end

  defp receive_useful_message(2, 1, socket) do
    IO.puts("Msg: interested")
  end

  defp receive_useful_message(3, 1, socket) do
    IO.puts("Msg: not interested")
  end

  defp receive_useful_message(4, 5, socket) do
    IO.puts("Msg: have")
  end

  defp receive_useful_message(5, length, socket) do
    IO.puts("Msg: bitfield")
  end

  defp receive_useful_message(6, 13, socket) do
    IO.puts("Msg: request")
  end

  defp receive_useful_message(7, length, socket) do
    IO.puts("Msg: piece")
  end

  defp receive_useful_message(8, 13, socket) do
    IO.puts("Msg: cancel")
  end

  defp receive_useful_message(id, length, _socket) do
    IO.puts("Msg: unknown #{id}, length #{length}")
  end

  defp receive_message_id(socket) do
    {:ok, <<msg_id::unsigned-integer-size(8)>>} = :gen_tcp.recv(socket, 1)
    msg_id
  end

  defp receive_handshake(socket) do
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

        %Peer{name: pstr, reserved: reserved, info_hash: info_hash, peer_id: peer_id}
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
