defmodule Edenflowers.Chat.Types.Source do
  use Ash.Type.Enum, values: [:agent, :user]
end
