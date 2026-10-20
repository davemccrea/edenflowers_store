defmodule EdenflowersWeb.CardDrawer do
  @moduledoc """
  The drawer of cards to choose from, at checkout and on Jennie's order form.
  Choosing one sends `select_card` with its `variant-id` to the LiveView.
  """
  use EdenflowersWeb, :html

  alias Edenflowers.Catalog.ProductVariantSize

  attr :variants, :list, required: true
  attr :locale, :string, required: true
  attr :selected_variant_id, :string, default: nil

  def card_drawer(assigns) do
    # The query sorts by size, so chunking keeps Small, Medium, Large in order.
    size_groups =
      assigns.variants
      |> Enum.chunk_by(& &1.size)
      |> Enum.map(fn [first | _] = variants ->
        {first.size, Enum.min_by(variants, & &1.price, Decimal).price, variants}
      end)

    assigns = assign(assigns, :size_groups, size_groups)

    ~H"""
    <.drawer
      id="card-drawer"
      placement="right"
      label={gettext("Select a card")}
      class="bg-base-100 w-[80vw] flex h-full flex-col overflow-y-auto overscroll-contain sm:w-[25rem] lg:w-[34rem]"
    >
      <header class="flex flex-row items-center justify-between gap-4 pt-6 pr-4 pl-4 sm:pt-8 sm:pl-8">
        <h2 class="section-title">{gettext("Select a card")}</h2>
        <.icon_button aria_label={~t"Close"} phx-click={JS.exec("phx-hide", to: "#card-drawer")}>
          <.icon name="hero-x-mark" class="h-6 w-6 hover:text-base-content/60" />
        </.icon_button>
      </header>

      <div class="flex flex-col gap-6 p-4 sm:p-8" data-testid="card-drawer">
        <div :for={{size, min_price, variants} <- @size_groups} class="flex flex-col gap-3">
          <div class="flex items-end justify-between gap-3">
            <div class="flex flex-col gap-1">
              <h3 class="eyebrow text-base-content/70">{size_label(size)}</h3>
              <span :if={character_limit_label(size)} class="text-base-content/70 text-sm">
                {character_limit_label(size)}
              </span>
            </div>
            <span class="font-serif text-lg">{Edenflowers.Format.currency(min_price, @locale)}</span>
          </div>
          <div class="grid grid-cols-2 gap-3 lg:grid-cols-3">
            <button
              :for={variant <- variants}
              type="button"
              phx-click={
                JS.push("select_card", value: %{"variant-id" => variant.id})
                |> JS.exec("phx-hide", to: "#card-drawer")
              }
              aria-current={variant.id == @selected_variant_id && "true"}
              class={["press relative flex flex-col items-center gap-1 border p-2 hover:border-primary", if(variant.id == @selected_variant_id,
    do: "border-primary bg-primary/5",
    else: "border-base-300")]}
              data-testid={"card-option-#{variant.id}"}
            >
              <span
                :if={variant.id == @selected_variant_id}
                class="bg-primary text-primary-content absolute top-3 right-3 flex h-5 w-5 items-center justify-center rounded-full"
              >
                <.icon name="hero-check-mini" class="h-3.5 w-3.5" />
              </span>
              <.image
                src={variant.image_slug}
                alt=""
                width={240}
                height={240}
                sizes="(min-width: 1024px) 10rem, 40vw"
                class="aspect-square w-full object-cover"
              />
              <%!-- Card names run to 16 characters, wider than a two-column tile on a phone. --%>
              <span class="font-serif text-balance hyphens-auto wrap-break-word w-full text-center text-lg leading-snug">
                {variant.product.name}
              </span>
              <%!-- Cards of one size usually share a price, already shown in the heading. --%>
              <span :if={not Decimal.equal?(variant.price, min_price)} class="font-serif text-lg">
                {Edenflowers.Format.currency(variant.price, @locale)}
              </span>
            </button>
          </div>
        </div>
      </div>
    </.drawer>
    """
  end

  defp size_label(:small), do: gettext("Small")
  defp size_label(:medium), do: gettext("Medium")
  defp size_label(:large), do: gettext("Large")
  defp size_label(nil), do: ""

  defp character_limit_label(nil), do: nil

  defp character_limit_label(size) do
    max_length = ProductVariantSize.max_message_length(size)
    ~t"Up to #{max_length} characters"
  end
end
