defmodule Bittorrent.File do
  @moduledoc """
  A single file in a BitTorrent download
  """

  defstruct [:path, :size]
end
