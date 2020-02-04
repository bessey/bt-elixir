defmodule Bittorrent.TorrentFile do
  @moduledoc """
  Functions for reading a .torrent file
  """
  alias Bittorrent.{Piece}

  defstruct [:announce, :info_hash, :pieces, :files, :piece_size]

  def extract_info(bencoded_binary) do
    torrent = Bento.decode!(bencoded_binary)
    piece_size = torrent["info"]["piece length"]

    # Hardcoded for single file mode for now
    file = %Bittorrent.File{
      path: torrent["info"]["name"],
      size: torrent["info"]["length"]
    }

    pieces =
      torrent["info"]["pieces"]
      |> piece_shas_from_binary
      |> Piece.from_shas(file.size, piece_size)

    %Bittorrent.TorrentFile{
      announce: torrent["announce"],
      info_hash: info_hash(torrent["info"]),
      piece_size: piece_size,
      files: [file],
      pieces: pieces
    }
  end

  defp info_hash(info) do
    bencoded = Bento.encode!(info)
    :crypto.hash(:sha, bencoded)
  end

  defp piece_shas_from_binary(binary) do
    for <<sha::binary-size(20) <- binary>>, into: [] do
      sha
    end
  end
end
