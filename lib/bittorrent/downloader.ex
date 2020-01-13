defmodule Bittorrent.Downloader do
  use GenServer
  alias Bittorrent.{Torrent, Piece}

  @blocks_in_progress_path "_blocks"
  @tmp_extension ".tmp"

  def in_progress_path(), do: @blocks_in_progress_path

  # Client

  def start_link(%Torrent{} = torrent) do
    GenServer.start_link(__MODULE__, torrent, name: :downloader)
  end

  def request_block(peer_pieces) do
    GenServer.call(:downloader, {:request_block, peer_pieces})
  end

  def block_downloaded(piece_index, begin, data) do
    GenServer.cast(:downloader, {:block_downloaded, piece_index, begin, data})
  end

  def peer_connected(peer_id, socket) do
    GenServer.cast(:downloader, {:peer_connected, peer_id, socket})
  end

  def peer_disconnected(peer_id) do
    GenServer.cast(:downloader, {:peer_disconnected, peer_id})
  end

  # Server (callbacks)

  @impl true
  def init(%Torrent{} = torrent) do
    {:ok, restore_from_progress(torrent)}
  end

  @impl true
  def handle_call({:request_block, peer_pieces}, _from, torrent) do
    requests = Torrent.blocks_we_need_that_peer_has(torrent.pieces, peer_pieces)
    {piece_index, block_index} = requests |> Enum.shuffle() |> List.first()
    IO.puts("Offering Piece #{piece_index} Block #{block_index}")
    {:reply, Torrent.request_for_block(torrent, piece_index, block_index), torrent}
  end

  @impl true
  def handle_cast({:block_downloaded, piece_index, begin, data}, torrent) do
    case Piece.block_for_begin(begin) do
      nil ->
        IO.puts("Bad block: #{piece_index}")
        {:noreply, torrent}

      block_index ->
        IO.puts("Block downloaded: #{piece_index}-#{block_index}")

        :ok =
          File.write(
            Path.join([
              torrent.output_path,
              @blocks_in_progress_path,
              "#{piece_index}-#{block_index}#{@tmp_extension}"
            ]),
            data
          )

        block_size = byte_size(data)

        {:noreply,
         Torrent.update_with_block_downloaded(
           torrent,
           piece_index,
           block_index,
           block_size
         )}
    end
  end

  @impl true
  def handle_cast({:peer_connected, peer_id, socket}, torrent) do
    {:noreply, %Torrent{torrent | connected_peers: [torrent.connected_peers | {peer_id, socket}]}}
  end

  @impl true
  def handle_cast({:peer_disconnected, peer_id}, torrent) do
    {:noreply,
     %Torrent{
       torrent
       | connected_peers: Enum.reject(torrent.connected_peers, &(&1[0] == peer_id))
     }}
  end

  # Utilities

  defp restore_from_progress(torrent) do
    blocks_path = Path.join([torrent.output_path, @blocks_in_progress_path])
    tmp_extension_index = -(String.length(@tmp_extension) + 1)

    {:ok, existing_blocks} = File.ls(blocks_path)

    existing_blocks
    |> Enum.map(&String.slice(&1, 0..tmp_extension_index))
    |> Enum.map(fn string -> String.split(string, "-") |> Enum.map(&String.to_integer/1) end)
    |> Enum.reduce(torrent, fn [piece_index, block_index], torrent ->
      IO.puts("Remembering we already downloaded #{piece_index}-#{block_index}")
      # TODO read block size
      Torrent.update_with_block_downloaded(torrent, piece_index, block_index, 0)
    end)
  end
end
