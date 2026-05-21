from pathlib import Path

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor

from build_final_report import (
    BASE,
    add_body,
    add_bullets,
    add_figure,
    add_heading,
    add_key_value_table,
    add_page_number,
    add_result_table,
    load_csv,
)


OUT = BASE / "SPACE312_Final_Project_Report_KR_final.docx"


def configure_styles(doc):
    section = doc.sections[0]
    section.top_margin = Inches(0.85)
    section.bottom_margin = Inches(0.85)
    section.left_margin = Inches(0.9)
    section.right_margin = Inches(0.9)
    add_page_number(section)

    styles = doc.styles
    for name in ["Normal", "Title", "Heading 1", "Heading 2", "Heading 3"]:
        styles[name].font.name = "Arial"
        styles[name]._element.rPr.rFonts.set(qn("w:eastAsia"), "Malgun Gothic")
    styles["Normal"].font.size = Pt(10.5)
    styles["Heading 1"].font.size = Pt(16)
    styles["Heading 2"].font.size = Pt(13)


def add_cover(doc, selected):
    doc.add_paragraph()
    title = doc.add_paragraph()
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = title.add_run("SPACE312 Final Project")
    run.bold = True
    run.font.size = Pt(25)
    run.font.color.rgb = RGBColor(31, 78, 121)

    subtitle = doc.add_paragraph()
    subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = subtitle.add_run("GTO-to-GEO Transfer Trajectory Optimization")
    run.bold = True
    run.font.size = Pt(17)

    target = doc.add_paragraph()
    target.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = target.add_run("Mission Target: GEO-KOMPSAT-2A")
    run.font.size = Pt(13)

    doc.add_paragraph()
    add_key_value_table(
        doc,
        [
            ("Course", "SPACE312 Space Flight Mechanics"),
            ("Project", "Final Project"),
            ("Student", "2024105257"),
            ("Initial epoch", "2026-06-01 00:00:00 UTC"),
            ("Mission priority", "Balanced design: propellant saving with short operational duration"),
            (
                "Selected design point",
                f"Delta t = {float(selected['TOF_days']):.4f} days, "
                f"total Delta V = {float(selected['dVtotal_km_s']):.4f} km/s",
            ),
        ],
    )

    lead = doc.add_paragraph()
    lead.alignment = WD_ALIGN_PARAGRAPH.CENTER
    lead.paragraph_format.space_before = Pt(24)
    run = lead.add_run(
        "This report selects one representative Pareto design after first defining the mission priority."
    )
    run.italic = True
    run.font.size = Pt(10.5)
    doc.add_page_break()


def add_toc(doc):
    add_heading(doc, "목차", 1)
    for item in [
        "1. 요약",
        "2. 과제 조건과 목표 상태 해석",
        "3. 수업 내용과의 연결",
        "4. Mission priority 설정",
        "5. 최적화 문제와 Pareto 평가",
        "6. 탐색 방법 및 코드 구성",
        "7. Pareto 결과와 knee point 판단",
        "8. 최종 대표 설계점",
        "9. 궤적, 오차, 가시성 결과",
        "10. 결론",
        "Appendix A. MATLAB 구현 요약",
    ]:
        p = doc.add_paragraph()
        p.paragraph_format.left_indent = Inches(0.15)
        p.paragraph_format.space_after = Pt(2)
        p.add_run(item)
    doc.add_page_break()


def find_selected(rows):
    return min(rows, key=lambda r: abs(float(r["TOF_days"]) - 1.2))


def build():
    rows = load_csv("FinalProject_ReportSolutions.csv")
    selected = find_selected(rows)
    fastest = rows[0]
    min_dv = rows[-1]

    doc = Document()
    configure_styles(doc)
    add_cover(doc, selected)
    add_toc(doc)

    add_heading(doc, "1. 요약", 1)
    add_body(
        doc,
        "본 과제는 초기 GTO 상태에서 GEO-KOMPSAT-2A의 목표 GEO 상태로 이동하는 impulsive transfer를 설계하고, "
        "총 Delta V와 transfer duration 사이의 Pareto 관계를 평가하는 문제이다. 교수님 답변에 따라 본 보고서에서는 "
        "먼저 mission priority를 '운용 시간이 과도하게 길지 않으면서 연료 소모를 크게 줄이는 균형 설계'로 정하였다."
    )
    add_body(
        doc,
        "그 기준에 따라 가장 빠른 해나 가장 작은 Delta V 해를 단순히 선택하지 않고, Pareto front에서 추가 시간 증가 대비 "
        "Delta V 절감 효과가 급격히 줄어들기 직전의 knee point를 대표 설계점으로 선정하였다. 최종 선택한 설계점은 "
        f"Delta t = {float(selected['TOF_days']):.4f} days, Delta V1 = {float(selected['dV1_km_s']):.4f} km/s, "
        f"Delta V2 = {float(selected['dV2_km_s']):.4f} km/s, total Delta V = "
        f"{float(selected['dVtotal_km_s']):.4f} km/s이다."
    )

    add_heading(doc, "2. 과제 조건과 목표 상태 해석", 1)
    add_body(
        doc,
        "초기 상태는 과제 안내 PDF의 GTO state vector를 그대로 사용하였다. 목표 상태 역시 교수님 답변에서 명시된 것처럼 "
        "Section 3.2의 target GEO state vector를 기준으로 사용하였다. 이 선택은 이번 과제에서 의도된 조건을 따르는 것이므로, "
        "별도의 원형 GEO 반경 재계산값으로 대체하지 않았다."
    )
    add_key_value_table(
        doc,
        [
            ("Initial GTO position", "[-42164.1729, 0, 0] km"),
            ("Initial GTO velocity", "[0, -1.458327, -0.664598] km/s"),
            ("Target GEO position", "[41244.6079, 12577.3213, 0] km"),
            ("Target GEO velocity", "[-0.917153, 2.934683, 0] km/s"),
            ("Dynamics", "Earth-centered two-body propagation"),
            ("Transfer time range", "1 day <= Delta t <= 30 days"),
        ],
    )
    add_body(
        doc,
        "이 목표 위치 벡터는 일반적인 원형 GEO 반경과 완전히 일치하도록 다시 만든 값이 아니라, 과제에서 의도적으로 제공된 "
        "target state이다. 따라서 코드에는 PDF_GIVEN 모드를 기본값으로 두어 Section 3.2의 수치를 그대로 사용하였다."
    )

    add_heading(doc, "3. 수업 내용과의 연결", 1)
    add_body(
        doc,
        "본 설계는 수업에서 다룬 개념을 조합해서 구성하였다. 따라서 최종 결과는 임의의 black-box optimizer가 아니라, "
        "강의에서 배운 궤도역학 절차를 코드로 반복 적용한 결과이다. 사용한 핵심 개념은 다음과 같다."
    )
    add_key_value_table(
        doc,
        [
            ("Two-body equation", "지구 중심 2체 문제로 GTO와 GEO state를 전파"),
            ("Impulsive maneuver", "출발과 도착에서 속도 벡터 차이로 Delta V 계산"),
            ("Lambert problem", "주어진 r1, r2, Delta t에 대해 transfer velocity 계산"),
            ("Inclination/plane change idea", "초기 GTO의 z방향 속도와 GEO의 equatorial 조건이 Delta V에 반영됨"),
            ("ECI to ECEF and SEZ", "KHU 지상국 기준 elevation과 visibility interval 계산"),
            ("Pork-chop/Pareto idea", "transfer time을 sweep하여 Delta V와 시간의 tradeoff를 비교"),
        ],
    )
    add_body(
        doc,
        "즉, 본 과제의 계산 흐름은 '시간을 하나 정한다 -> 해당 시각의 GEO 목표 state를 구한다 -> Lambert 문제를 푼다 -> "
        "두 번의 impulsive Delta V를 계산한다 -> 여러 시간 후보 중 Pareto 후보를 남긴다'이다. 이 방식은 수업에서 배운 "
        "Lambert transfer와 pork-chop 형태의 trade-space 탐색을 그대로 과제 조건에 적용한 것이다."
    )

    add_heading(doc, "4. Mission priority 설정", 1)
    add_body(
        doc,
        "GTO에서 GEO로 가는 임무에서는 연료 소모가 작을수록 좋지만, transfer 시간이 불필요하게 길어지면 위성 운용 시작이 늦어지고 "
        "추적, 관제, 초기 운용 리스크가 증가한다. 반대로 가장 빠른 해는 운용 일정 측면에서는 좋지만 Delta V penalty가 크다. "
        "따라서 본 설계의 mission priority는 다음과 같이 정의하였다."
    )
    add_bullets(
        doc,
        [
            "1순위: total Delta V를 빠른 1-day transfer 대비 충분히 줄일 것",
            "2순위: transfer duration을 과도하게 늘리지 않을 것",
            "3순위: 최종 위치 오차와 시각화 결과가 과제 요구 산출물로 검증 가능할 것",
        ],
    )
    add_body(
        doc,
        "이 우선순위에서는 minimum Delta V만을 절대 기준으로 삼지 않는다. Pareto front 위에서 '더 오래 기다릴수록 얻는 Delta V 절감'이 "
        "점점 작아지는 지점을 찾고, 그 지점을 대표 설계점으로 선택하는 것이 임무 관점에서 더 설득력 있다."
    )

    add_heading(doc, "5. 최적화 문제와 Pareto 평가", 1)
    add_body(
        doc,
        "각 후보해의 목적함수는 F = [total Delta V, transfer duration]으로 두었다. 한 후보해가 Pareto-optimal이라는 것은 "
        "다른 유효 후보해가 동시에 더 작은 Delta V와 더 짧은 시간을 제공하지 못한다는 뜻이다. 즉, Pareto front는 단일 정답이라기보다 "
        "임무 우선순위에 따라 대표 설계점을 고를 수 있는 최적 후보들의 집합이다."
    )
    add_bullets(
        doc,
        [
            "Delta V1 = ||v1_plus - v_GTO(t0)||",
            "Delta V2 = ||v_GEO(tf) - v2_minus||",
            "Total Delta V = Delta V1 + Delta V2",
            "Dominated candidate는 total Delta V와 transfer duration 중 적어도 하나가 더 나쁘고, 다른 하나도 개선되지 않는 후보이다.",
        ],
    )

    add_heading(doc, "6. 탐색 방법 및 코드 구성", 1)
    add_body(
        doc,
        "코드는 1일에서 30일까지의 transfer duration을 조밀하게 sweep하며 Lambert problem을 풀었다. 각 시간에 대해 목표 GEO state를 "
        "전파하고, 초기 GTO 위치에서 해당 목표 위치까지 연결하는 Lambert velocity를 구한 뒤 두 번의 impulsive maneuver 크기를 계산하였다."
    )
    add_body(
        doc,
        "중요한 점은 제출 결과가 MATLAB의 black-box 최적화 함수로 만들어진 것이 아니라는 점이다. 코드에는 검산용 direct-shooting 옵션이 "
        "남아 있지만 기본값은 false이며, 본 보고서의 표와 그림은 Lambert sweep 결과와 Pareto filtering만으로 생성하였다. 따라서 결과 해석은 "
        "수업에서 배운 Lambert transfer, two-body propagation, impulsive Delta V 계산에 기반한다."
    )
    add_body(
        doc,
        "기존에 검토했던 same-radius phasing 방식은 초기 GTO apogee 반경과 목표 반경이 같다는 조건에서 의미가 있다. 그러나 Section 3.2의 "
        "target state vector를 그대로 쓰면 목표 위치 벡터의 크기가 초기 apogee 반경과 약 955.5 km 다르다. 따라서 최종 코드에서는 PDF_GIVEN "
        "조건을 우선하고, same-point phasing 후보는 해당 반경 조건이 맞을 때만 추가되도록 제한하였다."
    )

    add_heading(doc, "7. Pareto 결과와 knee point 판단", 1)
    add_body(
        doc,
        "교수님 답변처럼 transfer 구성 방식에 따라 Pareto curve가 급격히 꺾이거나 설계 변수 변화에 따른 결과가 가파르게 나타날 수 있다. "
        "이번 결과에서도 1.0일에서 약 1.2일 부근까지는 시간을 조금 늘리는 것만으로 Delta V가 빠르게 감소하지만, 그 이후에는 추가 시간 대비 "
        "절감 폭이 작아진다. 이 변화율 감소가 knee point 선택의 핵심 근거이다."
    )
    add_result_table(doc, rows)
    add_figure(
        doc,
        "Pareto_dV_vs_TOF.png",
        "Figure 1. Pareto front of total Delta V versus transfer duration. The selected balanced point is near the knee.",
        width=6.2,
    )

    add_heading(doc, "8. 최종 대표 설계점", 1)
    add_body(
        doc,
        "최종 대표 설계점은 1.2000 days transfer이다. 이 해는 fastest 1-day case에 비해 transfer time을 0.2 days만 늘리면서 "
        "total Delta V를 상당히 줄인다. 반면 minimum-Delta V case까지 더 기다리면 추가 절감은 존재하지만, 본 mission priority에서 "
        "그만큼의 시간 증가를 대표 설계점으로 정당화하기는 어렵다."
    )
    add_key_value_table(
        doc,
        [
            ("Fastest valid case", f"{float(fastest['TOF_days']):.4f} days, {float(fastest['dVtotal_km_s']):.4f} km/s"),
            (
                "Selected balanced knee",
                f"{float(selected['TOF_days']):.4f} days, {float(selected['dVtotal_km_s']):.4f} km/s",
            ),
            ("Minimum-Delta V case", f"{float(min_dv['TOF_days']):.4f} days, {float(min_dv['dVtotal_km_s']):.4f} km/s"),
            (
                "Saving from fastest to selected",
                f"{float(fastest['dVtotal_km_s']) - float(selected['dVtotal_km_s']):.4f} km/s",
            ),
            (
                "Additional saving from selected to min-Delta V",
                f"{float(selected['dVtotal_km_s']) - float(min_dv['dVtotal_km_s']):.4f} km/s",
            ),
        ],
    )

    add_heading(doc, "9. 궤적, 오차, 가시성 결과", 1)
    add_body(
        doc,
        "선택한 궤적은 두 체 문제 전파와 Lambert boundary condition을 통해 최종 위치가 목표 위치에 도달하도록 구성되었다. "
        "3D 궤적, 반경 변화, maneuver 위치, 최종 위치 오차, KHU 기준 가시성 interval을 함께 확인하여 과제 요구 산출물을 검증하였다."
    )
    add_figure(doc, "Trajectory3D.png", "Figure 2. 3D trajectory from initial GTO state to target GEO state.", width=5.8)
    add_figure(doc, "Radius_vs_Time.png", "Figure 3. Radius history during the selected transfer.", width=5.8)
    add_figure(doc, "DeltaV_Maneuvers.png", "Figure 4. Maneuver locations and Delta V vectors.", width=5.8)
    add_figure(
        doc,
        "Position_Error_Final_Window.png",
        "Figure 5. Final position error near the target epoch.",
        width=5.8,
    )
    add_figure(doc, "KHU_Visibility.png", "Figure 6. Visibility interval from Kyung Hee University ground station.", width=5.8)

    add_heading(doc, "10. 결론", 1)
    add_body(
        doc,
        "본 설계는 과제 안내 PDF의 Section 3.2 target state vector를 기준 조건으로 사용하고, mission priority를 먼저 정의한 뒤 "
        "Pareto front에서 대표 설계점을 선택하였다. 최종 선택은 단순 최저 Delta V가 아니라, 짧은 운용 지연과 충분한 연료 절감 사이의 "
        "균형을 만족하는 1.2000-day knee point이다."
    )
    add_body(
        doc,
        "따라서 이 결과는 '최적해가 하나로 자동 결정된다'는 의미가 아니라, Pareto-optimal 후보군 중에서 임무 우선순위에 가장 맞는 해를 "
        "논리적으로 선택한 것이다. 그래프가 knee 형태로 급격히 변하는 점 역시 transfer 구성에 따라 가능한 현상이며, 본 결과에서는 그 knee가 "
        "대표 설계점 선정의 근거로 사용되었다."
    )

    add_heading(doc, "Appendix A. MATLAB 구현 요약", 1)
    add_bullets(
        doc,
        [
            "SPACE312_Final_Project_Main.m: main script, constants, target state mode, Lambert sweep, Pareto filtering, report solution selection",
            "targetStateMode = PDF_GIVEN: project PDF Section 3.2 target state vector를 그대로 사용",
            "runShootingRefinement = false: 제출 결과는 optimizer가 아니라 수업 기반 Lambert sweep으로 생성",
            "chooseBalancedKneeIndex: normalized Pareto front에서 knee point를 선택",
            "results/FinalProject_ParetoResults.csv: 전체 Pareto 후보 저장",
            "results/FinalProject_ReportSolutions.csv: 보고서용 대표 후보 저장",
            "results/balanced_knee: 최종 대표 설계점의 개별 그림과 case summary 저장",
        ],
    )

    doc.save(OUT)
    return OUT


if __name__ == "__main__":
    path = build()
    print(path)
