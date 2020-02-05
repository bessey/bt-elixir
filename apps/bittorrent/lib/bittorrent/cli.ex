defmodule Bittorrent.CLI do
  def main([]) do
    IO.puts("Usage:\nbittorrent --file ./my_torrent_file --output ./my_torrents/")
  end

  def main(args) do
    [file: file_path, output: output_path] = parse_args(args)
    Bittorrent.Worker.download(file_path, output_path)
  end

  defp parse_args(args) do
    {opts, _word, _invalid} =
      args
      |> OptionParser.parse(
        strict: [file: :string, output: :string],
        aliases: [f: :file, o: :output]
      )

    opts
  end
end
