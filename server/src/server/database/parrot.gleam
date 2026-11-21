import gleam/dynamic/decode.{type Decoder}
import gleam/list
import gleam/option.{None, Some}
import parrot/dev
import sqlight

/// Execute a Parrot-generated SQL statement with SQLight.
pub fn query(
  connection: sqlight.Connection,
  statement: #(String, List(dev.Param), Decoder(row)),
) -> Result(List(row), sqlight.Error) {
  let #(sql, parameters, decoder) = statement
  sqlight.query(
    sql,
    on: connection,
    with: list.map(parameters, parameter_to_sqlight),
    expecting: decoder,
  )
}

fn parameter_to_sqlight(parameter: dev.Param) -> sqlight.Value {
  case parameter {
    dev.ParamInt(value) -> sqlight.int(value)
    dev.ParamString(value) -> sqlight.text(value)
    dev.ParamFloat(value) -> sqlight.float(value)
    dev.ParamBool(value) -> sqlight.bool(value)
    dev.ParamBitArray(value) -> sqlight.blob(value)
    dev.ParamNullable(None) -> sqlight.null()
    dev.ParamNullable(Some(value)) -> parameter_to_sqlight(value)
    dev.ParamDynamic(_) ->
      panic as "Parrot dynamic SQL parameters are unsupported"
    dev.ParamTimestamp(_) ->
      panic as "Parrot timestamp SQL parameters are unsupported"
    dev.ParamDate(_) -> panic as "Parrot date SQL parameters are unsupported"
    dev.ParamList(_) -> panic as "Parrot list SQL parameters are unsupported"
  }
}
