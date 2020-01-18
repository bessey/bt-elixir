defmodule Bittorrent.PeerDownloader do
  use GenServer
  alias Bittorrent.{Downloader, Peer}

  defmodule State do
    defstruct [
      # Torrent Info
      :info_sha,
      :peer_id,
      :pieces_count,
      # Peer State
      peer: nil,
      task_pid: nil
    ]
  end

  # Client

  def start_link(%State{} = state) do
    GenServer.start_link(__MODULE__, state)
  end

  # Server

  @impl true
  def init(%State{} = state) do
    {:ok, peer_and_task_if_necessary(state)}
  end

  @impl true
  def handle_info({_task, {:ok, _result}}, state) do
    IO.puts("PeerDownloader: new connection")
    {:noreply, peer_and_task_if_necessary(%State{state | peer: nil, task_pid: nil})}
  end

  @impl true
  def handle_info({_task, {:error, reason}}, state) do
    IO.puts("PeerDownloader: new connection because error #{reason}")
    {:noreply, peer_and_task_if_necessary(%State{state | peer: nil, task_pid: nil})}
  end

  @impl true
  def handle_info(_, state), do: {:noreply, state}

  defp peer_and_task_if_necessary(state) do
    state = %State{state | peer: state.peer || request_peer()}
    %State{state | task_pid: state.task_pid || start_task(state)}
  end

  defp start_task(state) do
    Task.async(fn ->
      case Peer.Protocol.connect_to_peer(
             state.peer,
             state.info_sha,
             state.peer_id,
             state.pieces_count
           ) do
        {:ok, connected_peer, socket} ->
          Peer.Protocol.run_loop(connected_peer, socket)

        any ->
          any
      end
    end)
  end

  defp request_peer() do
    {:ok, peer} = Downloader.request_peer()
    peer
  end
end
