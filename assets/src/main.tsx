import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { TooltipProvider } from "./components/ui";
import App from "./App";
import MapPage from "./components/Map/MapPage";
import ClientsPage from "./components/Clients/ClientsPage";
import EventsPage from "./components/Events/EventsPage";
import VideoPage from "./components/Video/VideoPage";
import SettingsPage from "./components/Settings/SettingsPage";
import "@fontsource-variable/inter";
import "./styles/global.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <TooltipProvider>
      <BrowserRouter>
        <Routes>
          <Route element={<App />}>
            <Route path="/dashboard" element={<MapPage />} />
            <Route path="/dashboard/clients" element={<ClientsPage />} />
            <Route path="/dashboard/events" element={<EventsPage />} />
            <Route path="/dashboard/video" element={<VideoPage />} />
            <Route path="/dashboard/settings" element={<SettingsPage />} />
          </Route>
        </Routes>
      </BrowserRouter>
    </TooltipProvider>
  </StrictMode>
);
