defmodule Bittorrent.Downloader do
  use GenServer
  alias Bittorrent.Torrent

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

  def block_downloaded(block, data) do
    GenServer.cast(:downloader, {:block_downloaded, block, data})
  end

  # Server (callbacks)

  @impl true
  def init(%Torrent{} = torrent) do
    {:ok, restore_from_progress(torrent)}
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

    :ok =
      File.write(
        Path.join([torrent.output_path, @blocks_in_progress_path, "#{block}#{@tmp_extension}"]),
        data
      )

    pieces = Torrent.pieces_with_block_downloaded(torrent.pieces, block)
    {:noreply, %Torrent{torrent | pieces: pieces}}
  end

  # Utilities

  defp restore_from_progress(torrent) do
    blocks_path = Path.join([torrent.output_path, @blocks_in_progress_path])
    tmp_extension_index = -(String.length(@tmp_extension) + 1)

    {:ok, existing_blocks} = File.ls(blocks_path)

    pieces =
      existing_blocks
      |> Enum.map(&String.slice(&1, 0..tmp_extension_index))
      |> Enum.map(&String.to_integer/1)
      |> Enum.reduce(torrent.pieces, fn block, pieces ->
        IO.puts("Remembering we already downloaded #{block}")
        Torrent.pieces_with_block_downloaded(pieces, block)
      end)

    %Torrent{torrent | pieces: pieces}
  end
end
