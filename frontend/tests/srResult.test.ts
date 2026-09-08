import assert from "node:assert/strict";
import test from "node:test";

// @ts-expect-error -- Node's built-in TypeScript runner needs the extension.
import { parseSrResult } from "../lib/srResult.ts";

test("parses a structured SR output block", () => {
  const result = parseSrResult(`<sr_output>{
    "summary": {"candidate_count": 1},
    "sr_candidates": [{
      "candidate_key": "SRCAND-001",
      "disposition": "CREATE",
      "title": "元数据快速修复",
      "brief_description": "系统应缩短元数据修复时间。",
      "actor": "本系统",
      "preconditions": ["已创建硬盘域"],
      "minimum_guarantee": ["元数据修复成功"],
      "success_guarantee": ["元数据修复成功"],
      "trigger_event": "启动元数据修复",
      "main_success_scenarios": ["执行离线快速修复"],
      "extension_scenarios": ["盘故障时修复失败"],
      "constraints": [],
      "supported_products": ["Dorado：支持"],
      "traceability": {"function_impact_ids": ["FI-001"]},
      "confidence": "HIGH",
      "open_questions": [],
      "review_reasons": ["新建 SR"]
    }]
  }</sr_output>`);

  assert.ok(result);
  assert.equal(result.sr_candidates.length, 1);
  assert.equal(result.sr_candidates[0].title, "元数据快速修复");
  assert.deepEqual(result.sr_candidates[0].supported_products, [
    "Dorado：支持",
  ]);
});

test("uses legacy scenario aliases and rejects incomplete streaming blocks", () => {
  const result = parseSrResult(`<sr_output>{"sr_candidates":[{
    "title":"兼容数据",
    "requirement":"旧版正文",
    "normal_scenarios":["正常"],
    "exception_scenarios":["异常"]
  }]}</sr_output>`);

  assert.ok(result);
  assert.equal(result.sr_candidates[0].brief_description, "旧版正文");
  assert.deepEqual(result.sr_candidates[0].main_success_scenarios, ["正常"]);
  assert.equal(parseSrResult("<sr_output>{"), null);
});

test("keeps an empty SR result as structured UI data", () => {
  const result = parseSrResult(
    '<SR_OUTPUT>{"sr_candidates":[],"open_questions":["请补充输入"]}</SR_OUTPUT>'
  );

  assert.ok(result);
  assert.deepEqual(result.sr_candidates, []);
  assert.deepEqual(result.open_questions, ["请补充输入"]);
});
