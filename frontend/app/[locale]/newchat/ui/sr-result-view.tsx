"use client";

import { useMemo, useState } from "react";
import { ChevronRight, FileCheck2, ListChecks } from "lucide-react";

import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { cn } from "@/lib/utils";
import type { SrCandidate, SrResultPayload } from "@/lib/srResult";

const valueList = (value: unknown): string[] => {
  if (Array.isArray(value)) return value.map(String).filter(Boolean);
  if (typeof value === "string" && value.trim()) return [value.trim()];
  return [];
};

const traceSources = (candidate: SrCandidate): string => {
  if (!candidate.traceability) return "—";
  return (
    Object.values(candidate.traceability)
      .flatMap(valueList)
      .filter(Boolean)
      .slice(0, 4)
      .join("、") || "—"
  );
};

const badgeTone = (value: string) => {
  if (value === "CREATE" || value === "HIGH")
    return "bg-emerald-50 text-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-300";
  if (value === "UPDATE" || value === "MEDIUM")
    return "bg-amber-50 text-amber-700 dark:bg-amber-950/40 dark:text-amber-300";
  return "bg-slate-100 text-slate-700 dark:bg-slate-800 dark:text-slate-300";
};

const DetailField = ({
  label,
  value,
  ordered = false,
}: {
  label: string;
  value: string | string[];
  ordered?: boolean;
}) => {
  const values = Array.isArray(value) ? value : value ? [value] : [];
  return (
    <section className="space-y-1.5">
      <h3 className="text-sm font-semibold text-foreground">{label}</h3>
      {values.length === 0 ? (
        <p className="text-sm text-muted-foreground">不涉及</p>
      ) : ordered ? (
        <ol className="space-y-1 pl-5 text-sm leading-6 text-foreground/90">
          {values.map((item, index) => (
            <li key={`${label}-${index}`} className="list-decimal">
              {item}
            </li>
          ))}
        </ol>
      ) : (
        <ul className="space-y-1 pl-5 text-sm leading-6 text-foreground/90">
          {values.map((item, index) => (
            <li key={`${label}-${index}`} className="list-disc">
              {item}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
};

export const SrResultView = ({ result }: { result: SrResultPayload }) => {
  const [selected, setSelected] = useState<SrCandidate | null>(null);
  const reviewCount = useMemo(
    () =>
      result.sr_candidates.filter((item) => item.review_reasons.length > 0)
        .length,
    [result.sr_candidates]
  );

  return (
    <div className="my-3 overflow-hidden rounded-xl border border-border bg-background shadow-sm">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b bg-muted/35 px-4 py-3">
        <div className="flex items-center gap-2">
          <FileCheck2 className="size-5 text-blue-600" />
          <div>
            <h2 className="font-semibold">SR 生成结果</h2>
            <p className="text-xs text-muted-foreground">
              点击任意一行查看完整 SR 详情
            </p>
          </div>
        </div>
        <div className="flex gap-2 text-xs">
          <span className="rounded-full bg-blue-50 px-2.5 py-1 text-blue-700 dark:bg-blue-950/40 dark:text-blue-300">
            {result.sr_candidates.length} 条 SR
          </span>
          <span className="rounded-full bg-amber-50 px-2.5 py-1 text-amber-700 dark:bg-amber-950/40 dark:text-amber-300">
            {reviewCount} 条待审核
          </span>
        </div>
      </div>

      <div className="overflow-x-auto">
        <table className="w-full min-w-[720px] text-sm">
          <thead className="bg-muted/50 text-left text-xs text-muted-foreground">
            <tr>
              <th className="px-4 py-2.5 font-medium">编号</th>
              <th className="px-4 py-2.5 font-medium">SR 标题</th>
              <th className="px-4 py-2.5 font-medium">处理方式</th>
              <th className="px-4 py-2.5 font-medium">置信度</th>
              <th className="px-4 py-2.5 font-medium">追溯来源</th>
              <th className="w-10 px-2 py-2.5">
                <span className="sr-only">查看</span>
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {result.sr_candidates.map((candidate) => (
              <tr
                key={candidate.candidate_key}
                className="cursor-pointer transition-colors hover:bg-blue-50/60 focus-within:bg-blue-50/60 dark:hover:bg-blue-950/20"
                onClick={() => setSelected(candidate)}
              >
                <td className="whitespace-nowrap px-4 py-3 font-mono text-xs text-muted-foreground">
                  {candidate.candidate_key}
                </td>
                <td className="max-w-[320px] px-4 py-3 font-medium">
                  <button
                    type="button"
                    className="text-left hover:text-blue-600"
                    onClick={() => setSelected(candidate)}
                  >
                    {candidate.title}
                  </button>
                </td>
                <td className="px-4 py-3">
                  <span
                    className={cn(
                      "rounded-full px-2 py-1 text-xs font-medium",
                      badgeTone(candidate.disposition)
                    )}
                  >
                    {candidate.disposition}
                  </span>
                </td>
                <td className="px-4 py-3">
                  <span
                    className={cn(
                      "rounded-full px-2 py-1 text-xs font-medium",
                      badgeTone(candidate.confidence)
                    )}
                  >
                    {candidate.confidence}
                  </span>
                </td>
                <td className="max-w-[240px] truncate px-4 py-3 text-xs text-muted-foreground">
                  {traceSources(candidate)}
                </td>
                <td className="px-2 py-3 text-muted-foreground">
                  <ChevronRight className="size-4" />
                </td>
              </tr>
            ))}
            {result.sr_candidates.length === 0 && (
              <tr>
                <td
                  colSpan={6}
                  className="px-4 py-8 text-center text-sm text-muted-foreground"
                >
                  未生成新的 SR 候选，请查看待确认项或补充输入。
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {(result.open_questions?.length ?? 0) > 0 && (
        <div className="flex items-start gap-2 border-t bg-amber-50/60 px-4 py-3 text-xs text-amber-800 dark:bg-amber-950/20 dark:text-amber-200">
          <ListChecks className="mt-0.5 size-4 shrink-0" />
          <span>
            还有 {result.open_questions?.length} 个全局待确认问题，请在 SR
            详情中复核。
          </span>
        </div>
      )}

      <Sheet
        open={Boolean(selected)}
        onOpenChange={(open) => !open && setSelected(null)}
      >
        <SheetContent
          side="right"
          className="w-[min(92vw,760px)] overflow-y-auto sm:max-w-[760px]"
        >
          {selected && (
            <>
              <SheetHeader className="border-b pb-4 pr-8">
                <div className="flex flex-wrap gap-2 text-xs">
                  <span
                    className={cn(
                      "rounded-full px-2 py-1 font-medium",
                      badgeTone(selected.disposition)
                    )}
                  >
                    {selected.disposition}
                  </span>
                  <span
                    className={cn(
                      "rounded-full px-2 py-1 font-medium",
                      badgeTone(selected.confidence)
                    )}
                  >
                    {selected.confidence}
                  </span>
                  <span className="rounded-full bg-muted px-2 py-1">
                    {selected.candidate_key}
                  </span>
                </div>
                <SheetTitle className="text-xl leading-7">
                  {selected.title}
                </SheetTitle>
                <SheetDescription>完整系统需求详情</SheetDescription>
              </SheetHeader>

              <div className="space-y-5 py-5">
                <DetailField
                  label="1. 简要说明"
                  value={selected.brief_description}
                />
                <DetailField label="2. Actor" value={selected.actor} />
                <DetailField
                  label="3. 前置条件"
                  value={selected.preconditions}
                />
                <DetailField
                  label="4. 最小保证"
                  value={selected.minimum_guarantee}
                />
                <DetailField
                  label="5. 成功保证"
                  value={selected.success_guarantee}
                />
                <DetailField
                  label="6. 触发事件"
                  value={selected.trigger_event}
                />
                <DetailField
                  label="7. 主成功场景"
                  value={selected.main_success_scenarios}
                  ordered
                />
                <DetailField
                  label="8. 扩展场景（包括异常场景）"
                  value={selected.extension_scenarios}
                  ordered
                />

                <div className="grid gap-5 border-t pt-5 sm:grid-cols-2">
                  <DetailField label="约束" value={selected.constraints} />
                  <DetailField label="规格" value={selected.specification} />
                  <DetailField label="升级" value={selected.upgrade} />
                  <DetailField label="可靠性" value={selected.reliability} />
                  <DetailField label="性能" value={selected.performance} />
                  <DetailField label="安全" value={selected.security} />
                  <DetailField label="韧性" value={selected.resilience} />
                  <DetailField label="可服务" value={selected.serviceability} />
                  <DetailField label="可测试" value={selected.testability} />
                  <DetailField label="可定位" value={selected.locatability} />
                  <DetailField
                    label="是否申请大于 8K 连续内存"
                    value={selected.large_contiguous_memory}
                  />
                  <DetailField
                    label="支持的产品"
                    value={selected.supported_products}
                  />
                </div>

                <DetailField
                  label="9. 介质引入需求"
                  value={selected.media_requirements}
                />
                <DetailField
                  label="待确认问题"
                  value={selected.open_questions}
                />
                <DetailField
                  label="人工审核原因"
                  value={selected.review_reasons}
                />
                <DetailField label="追溯来源" value={traceSources(selected)} />
              </div>
            </>
          )}
        </SheetContent>
      </Sheet>
    </div>
  );
};
