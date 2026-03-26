import CesiumMap from "./CesiumMap";
import DetailSidebar from "./DetailSidebar";
import LayerPanel from "./LayerPanel";
import MapToolbar from "./MapToolbar";
import DrawingToolbar from "./DrawingToolbar";
import MeasureToolbar from "./MeasureToolbar";

export default function MapPage() {
  return (
    <div style={{ position: "relative", width: "100%", height: "100%" }}>
      <CesiumMap />
      <MapToolbar />
      <DrawingToolbar />
      <MeasureToolbar />
      <LayerPanel />
      <DetailSidebar />
    </div>
  );
}
