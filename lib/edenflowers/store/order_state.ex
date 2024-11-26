defmodule Edenflowers.Store.OrderState do
  use Ash.Type.Enum, values: [:cart, :completed]
end
