defmodule Bittorrent.Peer do
  @moduledoc """
  The guts of meaningfully communicating with a Peer we are connected to; leverage the protocol to get a peer
  to send us the pieces we need.
  """

  alias Bittorrent.Peer.{Protocol, Address}
  require Logger

  defmodule State do
    defstruct [
      # About them
      :name,
      :reserved,
      :info_hash,
      :id,
      :address,
      # Assume new peers have nothing until we know otherwise
      piece_set: MapSet.new(),
      socket: nil,
      # Their feelings for us
      choked: true,
      interested: false,
      # Our feelings for them
      interested_in: false,
      choking: true,
      # Stats
      requests_in_flight: 0
    ]

    def have_piece(peer, piece) do
      %Bittorrent.Peer.State{peer | piece_set: MapSet.put(peer.piece_set, piece)}
    end
  end

  @max_requests_in_flight 30
  @max_connection_frequency 30

  def connect(address, info_sha, peer_id) do
    Logger.info(
      "Connecting: #{to_string(address.ip)} #{address.port} #{address.last_connected_at}"
    )

    sleep_if_connected_recently(address.last_connected_at)

    with {:ok, socket} <-
           :gen_tcp.connect(
             address.ip,
             address.port,
             [:binary, packet: :raw, active: false, nodelay: true],
             3000
           ),
         {:ok, peer} <-
           Protocol.send_and_receive_handshake(
             info_sha,
             peer_id,
             address,
             socket
           ) do
      {:ok, %State{peer | address: Address.just_connected(peer.address)}, socket}
    else
      error -> error
    end
  end

  def run_loop(peer, socket) do
    :gen_tcp.recv(socket, 4) |> handle_run_loop_receive(peer, socket)
  end

  defp handle_run_loop_receive({:error, value}, _peer, _socket) do
    {:error, value}
  end

  defp handle_run_loop_receive({:ok, <<msg_length::unsigned-integer-size(32)>>}, peer, socket) do
    case peer
         |> Protocol.receive_message(msg_length, socket)
         |> send_loop(socket) do
      :error ->
        {:error, nil}

      peer ->
        run_loop(peer, socket)
    end
  end

  # If we are choking we cannot send messages until we tell the peer we are unchoked
  def send_loop(%State{choking: true} = peer, socket) do
    Protocol.send_unchoke(peer, socket)
  end

  # If the peer is choked there is no point sending messages, as they will be discarded
  def send_loop(%State{choked: false} = peer, socket) do
    if request = Bittorrent.Client.request_block(peer.piece_set) do
      peer |> ensure_interested(socket) |> ensure_requests_saturated(socket, request)
    else
      Protocol.send_not_interested(peer, socket)
    end
  end

  def send_loop(peer, _socket), do: peer

  defp ensure_interested(%State{interested_in: true} = peer, _socket), do: peer

  defp ensure_interested(%State{interested_in: false} = peer, socket) do
    Protocol.send_interested(peer, socket)
  end

  defp ensure_requests_saturated(%State{requests_in_flight: reqs} = peer, socket, request)
       when reqs < @max_requests_in_flight do
    peer
    |> Protocol.send_request(socket, request)
    |> send_loop(socket)
  end

  defp ensure_requests_saturated(peer_or_error, _socket, _request), do: peer_or_error

  defp sleep_if_connected_recently(nil), do: nil

  defp sleep_if_connected_recently(connected_at) do
    now = DateTime.utc_now()
    seconds_since_connection = DateTime.diff(now, connected_at, :second)

    unless(seconds_since_connection > @max_connection_frequency) do
      sleep_for =
        round(@max_connection_frequency - seconds_since_connection + :random.uniform() * 10)

      Logger.debug("Connected Too Recently: sleeping for #{sleep_for} seconds")
      Process.sleep(sleep_for * 1000)
    end
  end
end
