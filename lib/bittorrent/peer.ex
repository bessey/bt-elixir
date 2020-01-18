defmodule Bittorrent.Peer do
  alias Bittorrent.Peer.Protocol

  defmodule State do
    defstruct [
      # About them
      :name,
      :reserved,
      :info_hash,
      :id,
      :pieces,
      :ip,
      :port,
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
      pieces = List.replace_at(peer.pieces, piece, true)
      %Bittorrent.Peer.State{peer | pieces: pieces}
    end
  end

  @max_requests_in_flight 10

  def connect({ip, port}, info_sha, peer_id, pieces_count) do
    IO.puts("Connecting: #{to_string(ip)} #{port}")

    with {:ok, socket} <-
           :gen_tcp.connect(ip, port, [:binary, packet: :raw, active: false], 3000),
         {:ok, peer} <-
           Protocol.send_and_receive_handshake(
             info_sha,
             peer_id,
             pieces_count,
             ip,
             port,
             socket
           ) do
      {:ok, peer, socket}
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

  def send_loop(%State{choking: true} = peer, socket) do
    Protocol.send_unchoke(peer, socket)
  end

  def send_loop(%State{choked: false} = peer, socket) do
    if request = Bittorrent.Downloader.request_block(peer.pieces) do
      peer =
        if peer.interested_in do
          peer
        else
          Protocol.send_interested(peer, socket)
        end

      if peer.requests_in_flight < @max_requests_in_flight do
        send_request_and_loop(peer, socket, request)
      else
        peer
      end
    else
      Protocol.send_not_interested(peer, socket)
    end
  end

  def send_loop(peer, _socket), do: peer

  defp send_request_and_loop(peer, socket, request) do
    case Protocol.send_request(peer, socket, request) do
      :error ->
        :error

      peer ->
        if peer.requests_in_flight < @max_requests_in_flight do
          request = Bittorrent.Downloader.request_block(peer.pieces)
          send_request_and_loop(peer, socket, request)
        else
          peer
        end
    end
  end
end
