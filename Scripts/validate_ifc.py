"""Optional validation of an exported IFC. Run in an environment with IfcOpenShell.

python Scripts/validate_ifc.py survey.ifc --storeys 1 --pipes 3
This checks parsing, schema validation and geometry generation, not Revit acceptance.
"""
import argparse
import json
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("file")
    parser.add_argument("--storeys", type=int)
    parser.add_argument("--pipes", type=int)
    args = parser.parse_args()
    try:
        import ifcopenshell
        import ifcopenshell.geom
        import ifcopenshell.validate
    except ImportError:
        parser.error("Install IfcOpenShell in a separate validation environment.")
    model = ifcopenshell.open(args.file)
    logger = ifcopenshell.validate.json_logger()
    ifcopenshell.validate.validate(model, logger)
    failures = list(logger.statements)
    counts = {name: len(model.by_type(name)) for name in
              ["IfcBuildingStorey", "IfcWall", "IfcSpace", "IfcDistributionPort"]}
    segment_class = "IfcPipeSegment" if model.schema == "IFC4" else "IfcFlowSegment"
    counts[segment_class] = len(model.by_type(segment_class))
    if args.storeys is not None and counts["IfcBuildingStorey"] != args.storeys:
        failures.append({"message": "Unexpected storey count"})
    if args.pipes is not None and counts[segment_class] != args.pipes:
        failures.append({"message": "Unexpected segment count"})
    settings = ifcopenshell.geom.settings()
    for product in model.by_type("IfcProduct"):
        if product.Representation:
            try:
                ifcopenshell.geom.create_shape(settings, product)
            except Exception as error:
                failures.append({"message": str(error), "entity": product.id()})
    print(json.dumps({"schema": model.schema, "counts": counts, "issues": failures}, default=str, indent=2))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
