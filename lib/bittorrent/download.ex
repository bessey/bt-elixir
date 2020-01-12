defmodule Bittorrent.Downloader do
  use GenServer
  alias Bittorrent.Torrent

  # Client

  def start_link(%Torrent{} = torrent) do
    GenServer.start_link(__MODULE__, torrent, name: :downloader)
  end

  def request_block(peer_pieces) do
    GenServer.call(:downloader, {:request_block, peer_pieces})
  end

  def block_downloaded(block, data) do
    GenServer.cast(:downloader, {:block_downloaded, block, data})
  end

  # Server (callbacks)

  @impl true
  def init(%Torrent{} = torrent) do
    {:ok, torrent}
  end

  @impl true
  def handle_call({:request_block, peer_pieces}, _from, torrent) do
    blocks = Torrent.blocks_for_pieces(torrent, peer_pieces)
    block = blocks |> Enum.shuffle() |> List.first()
    IO.puts("Offering block: #{block}")
    {:reply, Torrent.request_for_block(torrent, block), torrent}
  end

  @impl true
  def handle_cast({:block_downloaded, block, data}, torrent) do
    IO.puts("Block downloaded: #{block}")
    :ok = File.write(Path.join([torrent.output_path, "_blocks", "#{block}.tmp"]), data)
    pieces = Torrent.pieces_with_block_downloaded(torrent.pieces, block)
    {:noreply, %Torrent{torrent | pieces: pieces}}
  end
end
