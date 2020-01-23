defmodule Bittorrent.Peer.Address do
  defstruct [:ip, :port, :last_connected_at]

  def just_connected(address) do
    %Bittorrent.Peer.Address{address | last_connected_at: DateTime.utc_now()}
  end
end
