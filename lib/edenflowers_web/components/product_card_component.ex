defmodule EdenflowersWeb.ProductCardComponent do
  use Phoenix.Component
  use EdenflowersWeb, :verified_routes
  import EdenflowersWeb.CoreComponents

  attr :product, :map, required: true
  attr :class, :string, default: nil

  def product_card(assigns) do
    ~H"""
    <li class={["group", @class]}>
      <.link navigate={~p"/product/#{@product.id}"} class="block">
        <div class="border-base-300 relative overflow-hidden rounded-lg border transition-all duration-300 hover:border-primary hover:shadow-lg">
          <div class="aspect-square bg-base-200 overflow-hidden">
            <img
              src={@product.image_slug}
              alt={@product.name}
              class="h-full w-full object-cover transition-transform duration-300 group-hover:scale-[1.05]"
            />
          </div>
          <div class="p-4">
            <h3 class="text-base-content line-clamp-1 text-lg font-semibold">
              {@product.name}
            </h3>
            <p class="text-primary mt-2 text-xl font-bold">
              {Edenflowers.Utils.format_money(@product.cheapest_price)}
            </p>
            <button class="btn btn-primary btn-sm mt-3 w-full">
              View details <.icon name="hero-arrow-right" class="h-4 w-4" />
            </button>
          </div>
        </div>
      </.link>
    </li>
    """
  end
end
