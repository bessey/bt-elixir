defmodule Bittorrent.Peer.Protocol do
  @moduledoc """
  Functions for sending and receiving messages conforming to the BitTorrent Peer Protocol
  """
  require Logger
  alias Bittorrent.{Peer.State}

  @pstr "BitTorrent protocol"
  @pstrlen String.length(@pstr)

  @msg_choke 0
  @msg_unchoke 1
  @msg_interested 2
  @msg_not_interested 3
  @msg_have 4
  @msg_bitfield 5
  @msg_request 6
  @msg_piece 7
  @msg_cancel 8

  # Receive Protocols

  def receive_message(peer, 0, __socket) do
    Logger.debug("Keep Alive")
    peer
  end

  def receive_message(peer, length, socket) do
    id = receive_message_id(socket)
    process_message(peer, id, length, socket)
  end

  def process_message(peer, @msg_choke, 1, _socket) do
    Logger.debug("Msg: choke")
    %State{peer | choked: true}
  end

  def process_message(peer, @msg_unchoke, 1, _socket) do
    Logger.debug("Msg: unchoke")
    %State{peer | choked: false}
  end

  def process_message(peer, @msg_interested, 1, _socket) do
    Logger.debug("Msg: interested")
    %State{peer | interested: true, choked: false}
  end

  def process_message(peer, @msg_not_interested, 1, _socket) do
    Logger.debug("Msg: not interested")
    %State{peer | interested: false, choked: false}
  end

  def process_message(peer, @msg_have, 5 = length, socket) do
    case :gen_tcp.recv(socket, length - 1) do
      {:ok, <<piece::unsigned-integer-size(32)>>} ->
        Logger.debug("Msg: have #{piece}")
        %State{State.have_piece(peer, piece) | choked: false}
    end
  end

  def process_message(peer, @msg_bitfield, length, socket) do
    Logger.debug("Msg: bitfield #{length}")

    case :gen_tcp.recv(socket, length - 1) do
      {:ok, <<bitfield::bits>>} ->
        %State{peer | piece_set: bitfield_to_piece_set(bitfield), choked: false}
    end
  end

  def process_message(peer, @msg_request, 13, _socket) do
    Logger.debug("Msg: request")
    peer
  end

  def process_message(peer, @msg_piece, length, socket) do
    case :gen_tcp.recv(socket, length - 1) do
      {:ok,
       <<
         piece_index::unsigned-integer-size(32),
         begin::unsigned-integer-size(32),
         data::binary
       >>} ->
        Logger.debug("Msg: piece #{piece_index}")
        Bittorrent.Client.block_downloaded(piece_index, begin, data)
        %State{peer | requests_in_flight: peer.requests_in_flight - 1}
    end
  end

  def process_message(peer, @msg_cancel, 13, _socket) do
    Logger.debug("Msg: cancel")
    peer
  end

  def process_message(peer, id, length, _socket) do
    Logger.debug("Msg: unknown id: #{id}, length: #{length}")
    raise "Stopping because unknown"
    peer
  end

  defp receive_message_id(socket) do
    {:ok, <<msg_id::unsigned-integer-size(8)>>} = :gen_tcp.recv(socket, 1)
    msg_id
  end

  def receive_handshake(socket, address) do
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
      Logger.debug("Connected: #{Base.encode64(peer_id)}")

      {:ok,
       %State{
         name: to_string(pstr),
         address: address,
         reserved: reserved,
         info_hash: info_hash,
         id: peer_id
       }}
    else
      error -> error
    end
  end

  # Send Protocols

  def send_and_receive_handshake(info_sha, peer_id, address, socket) do
    handshake = handshake_message(info_sha, peer_id)
    :ok = :gen_tcp.send(socket, handshake)
    receive_handshake(socket, address)
  end

  def send_request(peer, socket, {block, begin, block_size}) do
    Logger.debug("Send: request #{block} (#{peer.requests_in_flight + 1})")

    case :gen_tcp.send(socket, <<
           13::unsigned-integer-size(32),
           @msg_request::unsigned-integer-size(8),
           block::unsigned-integer-size(32),
           begin::unsigned-integer-size(32),
           block_size::unsigned-integer-size(32)
         >>) do
      :ok ->
        %State{peer | requests_in_flight: peer.requests_in_flight + 1}

      {:error, _} ->
        :error
    end
  end

  def send_interested(peer, socket) do
    Logger.debug("Send: interested")

    case :gen_tcp.send(
           socket,
           <<1::unsigned-integer-size(32), @msg_interested::unsigned-integer-size(8)>>
         ) do
      :ok ->
        %State{peer | interested_in: true}

      {:error, _} ->
        :error
    end
  end

  def send_not_interested(peer, socket) do
    Logger.debug("Send: not interested")

    case :gen_tcp.send(
           socket,
           <<1::unsigned-integer-size(32), @msg_not_interested::unsigned-integer-size(8)>>
         ) do
      :ok ->
        %State{peer | interested_in: false}

      {:error, _} ->
        :error
    end
  end

  def send_unchoke(peer, socket) do
    Logger.debug("Send: unchoke")

    case :gen_tcp.send(
           socket,
           <<1::unsigned-integer-size(32), @msg_unchoke::unsigned-integer-size(8)>>
         ) do
      :ok ->
        %State{peer | choking: false}

      {:error, _} ->
        :error
    end
  end

  def send_choke(peer, socket) do
    Logger.debug("Send: choke")

    case :gen_tcp.send(
           socket,
           <<1::unsigned-integer-size(32), @msg_choke::unsigned-integer-size(8)>>
         ) do
      :ok ->
        %State{peer | choking: true}

      {:error, _} ->
        :error
    end
  end

  # handshake: <pstrlen><pstr><reserved><info_hash><peer_id>
  def handshake_message(info_hash, peer_id) do
    <<
      # pstrlen: string length of <pstr>, as a single raw byte
      @pstrlen,
      # pstr: string identifier of the protocol
      @pstr,
      # reserved: eight (8) reserved bytes. All current implementations use all zeroes. Each bit in these bytes can be used to change the behavior of the protocol. An email from Bram suggests that trailing bits should be used first, so that leading bits may be used to change the meaning of trailing bits.
      0::unsigned-integer-size(64),
      # info_hash: 20-byte SHA1 hash of the info key in the metainfo file. This is the same info_hash that is transmitted in tracker requests.
      info_hash::binary,
      # peer_id: 20-byte string used as a unique ID for the client. This is usually the same peer_id that is transmitted in tracker requests (but not always e.g. an anonymity option in Azureus).
      peer_id::binary
    >>
  end

  defp bitfield_to_piece_set(bitfield) do
    for <<b::1 <- bitfield>>, into: [] do
      if(b == 1, do: true, else: false)
    end
    |> Enum.with_index()
    |> Enum.filter(fn {has_piece, _index} -> has_piece end)
    |> Enum.map(fn {_has_piece, index} -> index end)
    |> MapSet.new()
  end
end
