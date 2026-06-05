defmodule EdenflowersWeb.Admin.CinderTheme do
  @moduledoc """
  Cinder table theme for the admin.

  Extends the stock `daisy_ui` theme but remaps the filter-panel header away
  from DaisyUI's `card-title` class. The storefront redefines `card-title` as a
  large serif heading (see `assets/css/app.css`), which the admin's sans-serif,
  operational register should not inherit.

  The filter inputs are also pulled into the admin register: the selects drop
  to `sm` density to sit on the same scale as the compact data table beneath
  them. The per-filter labels are visually hidden — each select already shows
  an "All <field>" prompt that names the field, so a visible caption only
  duplicates it (and the column header below). The label stays in the markup as
  `sr-only` so screen readers still announce the control's name.
  """
  use Cinder.Theme

  extends :daisy_ui

  set :filter_header_class, "flex items-center justify-between mb-4"
  set :filter_title_class, "flex items-center gap-2 text-base font-semibold text-base-content"
  set :filter_count_class, "badge badge-primary badge-sm tabular-nums"

  set :filter_label_class, "sr-only"

  set :filter_text_input_class, "input input-bordered input-sm w-full"
  set :filter_select_input_class, "select select-bordered select-sm min-w-44"
end
