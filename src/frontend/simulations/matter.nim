## This module implements some types, variables and procedures to ease the use of matter-js

import std/[jsffi, math]

var
  Matter* {.importjs, nodecl.}: JsObject
  MatterWrap* {.importjs, nodecl.}: JsObject

type
  Vec* = tuple[x, y: float]

proc runOnce*(render: JsObject) = 
  ## Runs the render just once
  #_updateTiming(render, time);

  Matter.Render.world(render, 0)

  render.context.setTransform(render.options.pixelRatio, 0, 0, render.options.pixelRatio, 0, 0)
  render.context.setTransform(1, 0, 0, 1, 0, 0)

proc createEngine*(options: JsObject = nil): JsObject {.importjs: "Matter.Engine.create(#)".}
proc createRender*(options: JsObject): JsObject {.importjs: "Matter.Render.create(#)".}
proc jsVec*(x, y: SomeNumber or JsObject): JsObject = JsObject{x: x, y: y}
proc jsVec*(v: Vec): JsObject = JsObject{x: v.x, y: v.y}

proc setY*(body: JsObject, y: SomeNumber) = 
  Matter.Body.setPosition(body, JsObject{x: body.position.x, y: y})

proc setX*(body: JsObject, x: SomeNumber) = 
  Matter.Body.setPosition(body, JsObject{y: body.position.y, x: x})

proc setPos*(body: JsObject, x, y: SomeNumber or JsObject) = 
  Matter.Body.setPosition(body, JsObject{x: x, y: y})

proc getX*(body: JsObject): float = 
  body.position.x.to(float)

proc getY*(body: JsObject): float = 
  body.position.y.to(float)

proc getPos*(body: JsObject): tuple[x, y: float] = 
  (body.position.x.to(float), body.position.y.to(float))

proc vec*(v: JsObject): Vec = 
  (x: v.x.to(float), y: v.y.to(float))

proc sizeVec*(v: JsObject): Vec = 
  ## Expects v = JsObject{width: w, height: h}
  (x: v.width.to(float), y: v.height.to(float))

proc vec*(x, y: JsObject): Vec = 
  (x: x.to(float), y: y.to(float))

proc vec*(x, y: float): Vec = 
  (x: x, y: y)

proc `*`*(v1, v2: Vec): Vec =
  (x: v1.x * v2.x, y: v1.y * v2.y)

proc `+`*(v1, v2: Vec): Vec =
  (x: v1.x + v2.x, y: v1.y + v2.y)

proc `-`*(v1, v2: Vec): Vec =
  (x: v1.x - v2.x, y: v1.y - v2.y)

proc `/`*(v1, v2: Vec): Vec =
  (x: v1.x / v2.x, y: v1.y / v2.y)

proc `*`*(v1: Vec, a: float): Vec =
  (x: v1.x * a, y: v1.y * a)

proc `+`*(v1: Vec, a: float): Vec =
  (x: v1.x + a, y: v1.y + a)

proc `-`*(v1: Vec, a: float): Vec =
  (x: v1.x - a, y: v1.y - a)

proc `/`*(v1: Vec, a: float): Vec =
  (x: v1.x / a, y: v1.y / a)

proc distance*(v1, v2: Vec): float = 
  sqrt(abs((v2.x - v1.x)^2 + (v2.y - v1.y)^2))

proc distanceInt*(v1, v2: Vec): int = 
  int sqrt(abs((v2.x - v1.x)^2 + (v2.y - v1.y)^2))

proc distanceSquared*(v1, v2: Vec): float = 
  (v2.x - v1.x)^2 + (v2.y - v1.y)^2

proc inverted*(v: Vec): Vec = 
  vec(-v.x, -v.y)

proc invertedY*(v: Vec): Vec = 
  vec(v.x, -v.y)

proc invertedX*(v: Vec): Vec = 
  vec(-v.x, v.y)

proc invert*(v: var Vec) = 
  v.x = -v.x
  v.y = -v.y

proc invertY*(v: var Vec) = 
  v.y = -v.y

proc invertX*(v: var Vec) = 
  v.x = -v.x

proc both*(v: Vec, p: proc(a: float): float): Vec = 
  vec(p(v.x), p(v.y))
