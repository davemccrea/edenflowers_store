defmodule EdenflowersWeb.Admin.ProductFormLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components
  import EdenflowersWeb.Admin.PhotoUpload, only: [photo_input: 1]
  import EdenflowersWeb.Admin.TranslationFields

  alias Edenflowers.Catalog.Product
  alias Edenflowers.Catalog.ProductCategory
  alias Edenflowers.Catalog.ProductVariantSize
  alias Edenflowers.Pricing
  alias EdenflowersWeb.Admin.PhotoUpload
  alias EdenflowersWeb.Admin.TranslationFields
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(params, _session, socket) do
    actor = socket.assigns.current_user

    case load_form(params, actor) do
      {:ok, title, form} ->
        {:ok,
         socket
         |> assign(:page_title, title)
         |> assign(:categories, Ash.read!(ProductCategory, actor: actor))
         |> assign(:tax_rates, Pricing.list_selectable_tax_rates!(actor: actor))
         |> assign(:free_dist_km, Edenflowers.Fulfillment.free_dist_km())
         |> assign(:form, form)
         |> assign(:translating, nil)
         |> PhotoUpload.allow(photo_fields(form))}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, ~t"Product not found.")
         |> push_navigate(to: ~p"/admin/products")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={@page_title} back={{~t"Products", ~p"/admin/products"}}>
          <:subtitle :if={@form.source.type == :update}>
            <span id="product-status" class="inline-flex flex-wrap items-center gap-1.5">
              <.badge :if={@form.source.data.draft} tone={:neutral}>{~t"Draft"}</.badge>
              <.badge :if={!@form.source.data.draft} tone={:success}>{~t"Published"}</.badge>
              <.badge :if={@form.source.data.sold_out?} tone={:warning}>{~t"Sold out"}</.badge>
            </span>
          </:subtitle>
          <:actions>
            <.button
              :if={@form.source.type == :update && !@form.source.data.draft}
              href={~q"/#{language}/product/#{@form.source.data.id}"}
              target="_blank"
              variant="ghost"
              size="sm"
            >
              <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" /> {~t"View in store"}
            </.button>
            <.button type="submit" form="product-form" variant="primary" size="sm" phx-disable-with={~t"Saving…"}>
              {~t"Save"}
            </.button>
          </:actions>
        </.admin_page_header>

        <.form
          for={@form}
          id="product-form"
          data-warn-unsaved={~t"You have unsaved changes. Leave without saving?"}
          phx-change="validate"
          phx-submit="save"
          class="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1fr)_24rem] xl:items-start"
        >
          <div class="space-y-6">
            <.form_section title={~t"Name and description"}>
              <.language_fields form={@form} translating={@translating} />
            </.form_section>

            <.form_section title={~t"Sizes and prices"}>
              <:description>{~t"A new size without a photo gets the product photo."}</:description>
              <ul class="border-base-content/12 divide-base-content/8 divide-y border">
                <.inputs_for :let={variant} field={@form[:product_variants]}>
                  <li class="flex gap-4 p-4">
                    <.photo_input
                      field={variant[:image_slug]}
                      uploads={@uploads}
                      label={~t"Photo"}
                      size="sm"
                      show_errors={@form.source.submitted_once?}
                    />
                    <div class="min-w-0 flex-1 space-y-3 min-[1800px]:flex min-[1800px]:items-end min-[1800px]:gap-6 min-[1800px]:space-y-0">
                      <div class="grid grid-cols-1 gap-3 min-[1800px]:flex-1 sm:grid-cols-3">
                        <.input
                          field={variant[:size]}
                          type="select"
                          label={~t"Size"}
                          prompt={~t"One size"}
                          options={Enum.map(ProductVariantSize.values(), &{variant_size_label(&1), &1})}
                          class="select w-full"
                        />
                        <.input
                          field={variant[:price]}
                          type="text"
                          inputmode="decimal"
                          label={~t"Price (€)"}
                          class="input w-full tabular-nums"
                        />
                        <%!-- ponytail: saving sends the count shown when the form opened, so a sale made
                             meanwhile is undone and may oversell later. Send only changed counts if that bites. --%>
                        <.input
                          field={variant[:stock_quantity]}
                          type="number"
                          min="0"
                          label={~t"In stock"}
                          placeholder={~t"Unlimited"}
                          class="input w-full tabular-nums"
                        />
                      </div>
                      <div class="flex flex-wrap items-center gap-x-6 gap-y-2 min-[1800px]:shrink-0 min-[1800px]:flex-nowrap">
                        <.input field={variant[:draft]} type="checkbox" label={~t"Draft"} />
                        <.button
                          type="button"
                          phx-click="remove_variant"
                          phx-value-path={variant.name}
                          variant="ghost"
                          size="sm"
                          class="text-error ml-auto"
                        >
                          {~t"Remove"}
                        </.button>
                      </div>
                    </div>
                  </li>
                </.inputs_for>
                <li>
                  <button
                    type="button"
                    phx-click="add_variant"
                    class="text-base-content/80 flex w-full items-center gap-2 p-4 text-sm font-medium transition-colors hover:bg-base-200/60 hover:text-base-content"
                  >
                    <.icon name="hero-plus" class="h-4 w-4" />
                    {~t"Add size"}
                  </button>
                </li>
              </ul>
              <div class="mt-3 flex flex-wrap items-end justify-between gap-4">
                <div class="w-full sm:w-64">
                  <.input
                    field={@form[:tax_rate_id]}
                    type="select"
                    label={~t"VAT"}
                    options={Enum.map(@tax_rates, &{&1.name, &1.id})}
                    class="select w-full"
                  />
                </div>
                <.button type="button" phx-click="mark_sold_out" variant="ghost" size="sm" data-testid="mark-sold-out">
                  {~t"Mark every size sold out"}
                </.button>
              </div>
            </.form_section>
          </div>

          <aside class="flex flex-col gap-6 xl:row-span-2">
            <.form_section title={~t"Photo"}>
              <.photo_input
                field={@form[:image_slug]}
                uploads={@uploads}
                label={~t"Photo"}
                show_errors={@form.source.submitted_once?}
              />
            </.form_section>

            <.form_section title={~t"In the store"}>
              <div class="space-y-4">
                <div class="grid grid-cols-1 gap-4">
                  <.input
                    field={@form[:product_category_id]}
                    type="select"
                    label={~t"Category"}
                    prompt={~t"Choose a category"}
                    options={Enum.map(@categories, &{&1.name, &1.id})}
                    class="select w-full"
                  />
                  <.input
                    field={@form[:position]}
                    type="number"
                    min="0"
                    label={~t"Position in store (0 = first)"}
                    class="input max-w-48 w-full tabular-nums"
                  />
                </div>
                <div>
                  <.input field={@form[:draft]} type="checkbox" label={~t"Draft"} />
                  <.input field={@form[:featured]} type="checkbox" label={~t"Featured on the home page"} />
                  <.input
                    :if={@free_dist_km}
                    field={@form[:free_delivery]}
                    type="checkbox"
                    label={~t"Free delivery within #{km = @free_dist_km} km"}
                  />
                  <.input
                    field={@form[:subscribable]}
                    type="checkbox"
                    label={~t"Can be bought as a subscription"}
                  />
                </div>
              </div>
            </.form_section>
          </aside>

          <%!-- After the aside so its fields sit above Save once stacked. --%>
          <.button
            type="submit"
            variant="primary"
            phx-disable-with={~t"Saving…"}
            class="w-full sm:w-auto sm:justify-self-start xl:col-start-1"
          >
            {~t"Save product"}
          </.button>
        </.form>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    params =
      params
      |> PhotoUpload.merge_slugs(socket, photo_fields(socket.assigns.form))
      |> default_size_photos(socket.assigns.form)

    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  # Fills each size's stock with 0; nothing is saved until Jennie saves.
  def handle_event("mark_sold_out", _params, socket) do
    form = socket.assigns.form
    params = form.source.params

    sizes =
      for size <- form.source.forms[:product_variants] || [], into: %{} do
        key = size.name |> String.split(["[", "]"], trim: true) |> List.last()
        {key, Map.put(params["product_variants"][key] || %{}, "stock_quantity", "0")}
      end

    params = Map.put(params, "product_variants", Map.merge(params["product_variants"] || %{}, sizes))
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(form, params))}
  end

  def handle_event("add_variant", _params, socket) do
    socket = update(socket, :form, &AshPhoenix.Form.add_form(&1, "form[product_variants]"))
    {:noreply, PhotoUpload.allow(socket, photo_fields(socket.assigns.form))}
  end

  # Removing a size renumbers the ones after it, so pending size photos would
  # land on the wrong size. Clearing them is simpler than remapping.
  def handle_event("remove_variant", %{"path" => path}, socket) do
    socket = PhotoUpload.forget(socket, variant_photo_fields(socket.assigns.form))
    {:noreply, update(socket, :form, &AshPhoenix.Form.remove_form(&1, path))}
  end

  def handle_event("translate", %{"from" => from}, socket),
    do: {:noreply, TranslationFields.translate(socket, from)}

  def handle_event("save", %{"form" => params}, socket) do
    names = photo_fields(socket.assigns.form)
    socket = PhotoUpload.store_uploads(socket, names)
    params = params |> PhotoUpload.merge_slugs(socket, names) |> default_size_photos(socket.assigns.form)

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _product} ->
        {:noreply,
         socket
         |> put_flash(:info, ~t"Product saved.")
         |> push_navigate(to: ~p"/admin/products")}

      {:error, form} ->
        {:noreply,
         socket
         |> assign(:form, form)
         |> put_flash(:error, ~t"The product wasn't saved. Check the fields marked below.")}
    end
  end

  @impl true
  def handle_async(:translate, result, socket),
    do: {:noreply, TranslationFields.put_translations(socket, result)}

  defp load_form(%{"id" => id}, actor) do
    case Ash.get(Product, id, actor: actor, load: [:product_variants, :sold_out?]) do
      {:ok, product} ->
        form = AshPhoenix.Form.for_update(product, :update, actor: actor) |> TranslationFields.add_forms()
        {:ok, product.name, to_form(form)}

      {:error, _} ->
        :error
    end
  end

  defp load_form(_params, actor) do
    form =
      AshPhoenix.Form.for_create(Product, :create, actor: actor)
      |> TranslationFields.add_forms()
      |> AshPhoenix.Form.add_form("form[product_variants]", validate?: false)

    {:ok, ~t"New product", to_form(form)}
  end

  # A new size without its own photo shows the product's. Saved sizes are left
  # alone: they already have a photo, and it may differ on purpose.
  defp default_size_photos(params, form) do
    product_photo = params["image_slug"] || (form.source.data && form.source.data.image_slug)

    new_sizes =
      for size <- form.source.forms[:product_variants] || [], size.type == :create do
        size.name |> String.split(["[", "]"], trim: true) |> List.last()
      end

    case params do
      %{"product_variants" => sizes} when is_binary(product_photo) ->
        sizes =
          Map.new(sizes, fn {key, size} ->
            if key in new_sizes, do: {key, Map.put_new(size, "image_slug", product_photo)}, else: {key, size}
          end)

        Map.put(params, "product_variants", sizes)

      _ ->
        params
    end
  end

  defp photo_fields(form), do: ["form[image_slug]" | variant_photo_fields(form)]

  defp variant_photo_fields(form) do
    Enum.map(form.source.forms[:product_variants] || [], &(&1.name <> "[image_slug]"))
  end
end
