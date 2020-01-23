defmodule Bittorrent.PeerDownloader do
  @moduledoc """
  Server in charge of maintaining a connection with a single Peer and downloading blocks from them
  """

  require Logger
  use GenServer
  alias Bittorrent.{Downloader, Peer}

  defmodule State do
    defstruct [
      # Torrent Info
      :info_sha,
      :peer_id,
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
    Logger.debug("PeerDownloader: new connection")
    {:noreply, peer_and_task_if_necessary(%State{state | peer: nil, task_pid: nil})}
  end

  @impl true
  def handle_info({_task, {:error, reason}}, state) do
    Logger.debug("PeerDownloader: new connection because error #{reason}")
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
      case Peer.connect(
             state.peer,
             state.info_sha,
             state.peer_id
           ) do
        {:ok, connected_peer, socket} ->
          Logger.metadata(peer: elem(state.peer, 0))
          Logger.metadata(info_sha: Base.encode64(state.info_sha))
          Peer.run_loop(connected_peer, socket)

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
