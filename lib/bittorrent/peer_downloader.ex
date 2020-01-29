defmodule Bittorrent.PeerDownloader do
  @moduledoc """
  Server in charge of maintaining a connection with a single Peer and downloading blocks from them
  """

  require Logger
  use GenServer
  alias Bittorrent.{Client, Peer}

  defmodule State do
    defstruct [
      # Torrent Info
      :info_sha,
      :peer_id,
      # Peer State
      address: nil,
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
  def handle_info({_task, {:ok, _address}}, state) do
    Logger.debug("PeerDownloader: new connection")
    {:noreply, peer_and_task_if_necessary(%State{state | address: nil, task_pid: nil})}
  end

  @impl true
  def handle_info({_task, {:error, address, reason}}, state) do
    Logger.debug("PeerDownloader: new connection because error #{reason}")
    Client.return_peer(address)
    {:noreply, peer_and_task_if_necessary(%State{state | address: nil, task_pid: nil})}
  end

  @impl true
  def handle_info({_task, :retry_peer_fetch}, state) do
    {:noreply, peer_and_task_if_necessary(state)}
  end

  @impl true
  def handle_info(_, state), do: {:noreply, state}

  defp peer_and_task_if_necessary(state) do
    address = state.address || request_peer()

    if address do
      state = %State{state | address: address}
      %State{state | task_pid: state.task_pid || start_task(state)}
    else
      Logger.debug("PeerDownloader: no peer available, sleeping")
      Process.send_after(self(), :retry_peer_fetch, 30 * 1000)
      state
    end
  end

  defp start_task(state) do
    Task.async(fn ->
      Logger.metadata(peer: state.address.ip)
      Logger.metadata(info_sha: Base.encode64(state.info_sha))

      case Peer.connect(
             state.address,
             state.info_sha,
             state.peer_id
           ) do
        {:ok, connected_peer, socket} ->
          {:error, reason} = Peer.run_loop(connected_peer, socket)
          {:error, connected_peer.address, reason}

        {:error, reason} ->
          {:error, Peer.Address.just_connected(state.address), reason}
      end
    end)
  end

  defp request_peer() do
    {:ok, peer} = Client.request_peer()
    peer
  end
end
