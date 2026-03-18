import CesiumMap from "./CesiumMap";
import DetailSidebar from "./DetailSidebar";
import LayerPanel from "./LayerPanel";
import DrawingToolbar from "./DrawingToolbar";

export default function MapPage() {
  return (
    <div style={{ position: "relative", width: "100%", height: "100%" }}>
      <CesiumMap />
      <DrawingToolbar />
      <LayerPanel />
      <DetailSidebar />
    </div>
  );
}
