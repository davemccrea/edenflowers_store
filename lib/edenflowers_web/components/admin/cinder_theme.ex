defmodule EdenflowersWeb.Admin.CinderTheme do
  @moduledoc """
  Cinder table theme for the admin.

  Extends the stock `daisy_ui` theme but remaps the filter-panel header away
  from DaisyUI's `card-title` class. The storefront redefines `card-title` as a
  large serif heading (see `assets/css/app.css`), which the admin's sans-serif,
  operational register should not inherit.

  The filter inputs are also pulled into the admin register: the selects and
  search box drop to `sm` density to sit on the same scale as the compact data
  table beneath them. Each filter shows a visible caption above its control so
  the panel reads as a labelled form; the select prompts are then a bare "All",
  since the caption already names the field. Captions are set per filter (via
  the `:label` filter option) because the table column headers are terser than
  a standalone caption wants to be — and two of them would otherwise both read
  "Fulfillment".
  """
  use Cinder.Theme

  extends :daisy_ui

  set :container_class, "min-w-0"
  set :controls_class, "card card-sm card-border bg-base-100 mb-4 overflow-visible"
  set :table_wrapper_class, "card card-border bg-base-100 overflow-x-auto max-w-full"
  set :table_class, "table table-zebra w-full min-w-max"
  set :td_class, "align-top"

  set :filter_header_class, "flex items-center justify-between mb-4"
  set :filter_title_class, "flex items-center gap-2 text-base font-semibold text-base-content"
  set :filter_count_class, "badge badge-primary badge-sm tabular-nums"
  set :filter_container_class, "card-body p-4 sm:p-5"
  set :filter_inputs_class, "fieldset grid grid-cols-1 gap-4 sm:grid-cols-2 lg:flex lg:flex-wrap"
  set :filter_input_wrapper_class, "form-control min-w-0"

  set :filter_label_class, "label-text mb-1 block text-xs font-medium text-base-content/65"

  set :filter_text_input_class, "input input-bordered input-sm w-full"
  set :filter_date_input_class, "input input-bordered input-sm w-full sm:w-40"

  set :filter_number_input_class,
      "input input-bordered input-sm w-full sm:w-24 [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none [-moz-appearance:textfield]"

  set :filter_select_input_class, "select select-bordered select-sm w-full min-w-0 sm:min-w-44"
  set :filter_range_container_class, "flex flex-col gap-2 sm:flex-row sm:items-center"

  # Stock daisy_ui clears with a `btn-ghost` button — transparent until hover, so
  # a lone "×" is easy to miss when a filter is active. Swap to an outlined chip
  # that carries a visible border at rest (matching the bordered inputs beside
  # it), then warms to error-red on hover so its purpose reads. `btn-sm btn-square`
  # keeps the glyph centred and the target above the 24px WCAG 2.2 minimum.
  set :filter_clear_button_class,
      "btn btn-outline btn-sm btn-square ml-2 border-base-content/20 text-base-content/65 hover:border-error hover:bg-error/10 hover:text-error"

  # Match the search box to the `sm` density of the filter inputs above; the
  # stock daisy_ui theme leaves it at the default (taller) input height, which
  # makes it tower over the selects it sits beside. `pl-10` preserves room for
  # the search icon the renderer overlays.
  set :search_input_class, "input input-bordered input-sm w-full pl-10"

  set :pagination_container_class, "flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"
  set :pagination_info_class, "text-sm"
  set :pagination_count_class, "text-base-content/50 block text-xs sm:ml-2 sm:inline"
  set :pagination_nav_class, "flex flex-wrap items-center gap-1 sm:flex-nowrap"
  set :page_size_container_class, "flex items-center gap-2"
end
